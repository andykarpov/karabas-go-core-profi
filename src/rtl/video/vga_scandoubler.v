`timescale 1ns / 1ps
`default_nettype none

//    This file is part of the ZXUNO Spectrum core. 
//    Creation date is 17:57:54 2015-09-11 by Miguel Angel Rodriguez Jodar
//    (c)2014-2020 ZXUNO association.
//    ZXUNO official repository: http://svn.zxuno.com/svn/zxuno
//    Username: guest   Password: zxuno
//    Github repository for this core: https://github.com/mcleod-ideafix/zxuno_spectrum_core
//
//    ZXUNO Spectrum core is free software: you can redistribute it and/or modify
//    it under the terms of the GNU General Public License as published by
//    the Free Software Foundation, either version 3 of the License, or
//    (at your option) any later version.
//
//    ZXUNO Spectrum core is distributed in the hope that it will be useful,
//    but WITHOUT ANY WARRANTY; without even the implied warranty of
//    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//    GNU General Public License for more details.
//
//    You should have received a copy of the GNU General Public License
//    along with the ZXUNO Spectrum core.  If not, see <https://www.gnu.org/licenses/>.
//
//    Any distributed copy of this file must keep this notice intact.

module vga_scandoubler (
  input wire clk,
  input wire clk28en,
  input wire clk14en,
  input wire enable_scandoubling,
  input wire disable_scaneffect,  // 1 to disable scanlines
  input wire ds80,
  input wire [1:0] screen_mode,
  input wire [2:0] ri,
  input wire [2:0] gi,
  input wire [2:0] bi,
  input wire hsync_ext_n,
  input wire vsync_ext_n,
  input wire csync_ext_n,
  input wire blanki,
  output reg [5:0] ro,
  output reg [5:0] go,
  output reg [5:0] bo,
  output reg hsync,
  output reg vsync,
  output reg blank
  );
 
  parameter [31:0] CLKVIDEO = 12000;
 
  // http://www.epanorama.net/faq/vga2rgb/calc.html
  // SVGA 800x600
  // HSYNC = 3.36us  VSYNC = 114.32us
  
  parameter [63:0] HSYNC_COUNT = (CLKVIDEO * 3360 * 2)/1000000; // 80
  parameter [63:0] VSYNC_COUNT = (CLKVIDEO * 114320 * 2)/1000000; // 2744

	// счетчики hcnt и vcnt начинаются с началом синхры.
	// соотв. для расчета blank мы считаем синхру + back porche от начала отсчета, а в конце строки или кадра - 
	// отнимаем front porche

  // в режиме пентагона горизонтальная и вертикальная синхронизация не имеет front porche
  parameter [9:0] SPEC_BLANK_H = 128; // (0 fp + 32 hs + 32 bp) * 2
  parameter [9:0] SPEC_BLANK_V = 64; // (16 vs) * 2

  // в режиме профи горизонтальная и вертикальная синхра начинается после front porche,
  // поэтому в условиях blank_h и blank_v при ds80=1 условие чуть сложнее
  parameter [9:0] PROF_BLANK_H = 128; //224; // (32 fp + 64 hs + 64 bp)
  parameter [9:0] PROF_BLANK_V = 64; // (16 fp + 32 vs + 32 bp)

	// счетчики
  reg [10:0] hcnt = 11'd0, vcnt = 11'd0;  
  
  // spec: 896x640 full, hdmi 576p: 768x576 (896-768=128, 640-576=64)
  // profi:768x640 full, hdmi 576p: 544x576 (768-544=224, 640-576=64)

	// сигналы горизонтального и вертикального blank
  wire blank_h = (ds80) ? (hcnt < PROF_BLANK_H) : (hcnt < SPEC_BLANK_H);
  wire blank_v = (ds80) ? (vcnt < PROF_BLANK_V) : (vcnt < SPEC_BLANK_V);

	// ------------------------------------------------------------------
 
  reg [10:0] addrvideo = 11'd0, addrvga = 11'b00000000000;
  reg [9:0] totalhor = 10'd0;
  

  wire [2:0] rout, gout, bout;
  // Memoria de doble puerto que guarda la informacin de dos scans
  // Cada scan puede ser de hasta 1024 puntos, incluidos aqu los
  // puntos en negro que se pintan durante el HBlank

  vgascanline_dport memscan (
    .clk(clk),
	 .clk28en(clk28en),
    .addrwrite(addrvideo),
    .addrread(addrvga),
    .we(clk14en),
    .din({ri,gi,bi}),
    .dout({rout,gout,bout})
  );

  // Para generar scanlines:
  reg scaneffect = 1'b0;
  wire [2:0] rout_dimmed, gout_dimmed, bout_dimmed;
  color_dimmed apply_to_red   (rout, rout_dimmed);
  color_dimmed apply_to_green (gout, gout_dimmed);
  color_dimmed apply_to_blue  (bout, bout_dimmed);
  wire [2:0] ro_vga = (scaneffect | disable_scaneffect)? rout : rout_dimmed;
  wire [2:0] go_vga = (scaneffect | disable_scaneffect)? gout : gout_dimmed;
  wire [2:0] bo_vga = (scaneffect | disable_scaneffect)? bout : bout_dimmed;
  
  // Voy alternativamente escribiendo en una mitad o en otra del scan buffer
  // Cambio de mitad cada vez que encuentro un pulso de sincronismo horizontal
  // En "totalhor" mido el nmero de ciclos de reloj que hay en un scan
  reg hsync_ext_n_prev = 1'b1;
  always @(posedge clk) begin
    if (clk28en == 1'b1 && clk14en == 1'b1) begin
      hsync_ext_n_prev <= hsync_ext_n;
      if (hsync_ext_n == 1'b0 && hsync_ext_n_prev == 1'b1) begin
        totalhor <= addrvideo[9:0];
        addrvideo <= {~addrvideo[10],10'b0000000000};
      end
      else
        addrvideo <= addrvideo + 11'd1;
    end
  end
 
  // Recorro el scanbuffer al doble de velocidad, generando direcciones para
  // el scan buffer. Cada vez que el video original ha terminado una linea,
  // cambio de mitad de buffer. Cuando termino de recorrerlo pero an no
  // estoy en un retrazo horizontal, simplemente vuelvo a recorrer el scan buffer
  // desde el mismo origen
  // Cada vez que termino de recorrer el scan buffer basculo "scaneffect" que
  // uso despus para mostrar los pxeles a su brillo nominal, o con su brillo
  // reducido para un efecto chachi de scanlines en la VGA
 
  reg hsync_ext_n_prev2 = 1'b1;
  always @(posedge clk) begin
	 if (clk28en == 1'b1) begin
      hsync_ext_n_prev2 <= hsync_ext_n;
      if (addrvga[9:0] == totalhor && hsync_ext_n == 1'b1 && hsync_ext_n_prev2 == 1'b1) begin
         addrvga <= {addrvga[10], 10'b000000000};
         scaneffect <= ~scaneffect;
      end
      else if (hsync_ext_n == 1'b0 && hsync_ext_n_prev2 == 1'b1 /*&& addrvga[9] == 1'b0*/) begin
        addrvga <= {addrvideo[10],10'b000000000};
        scaneffect <= ~scaneffect;
      end
      else
        addrvga <= addrvga + 11'd1;
	 end
  end

  // El HSYNC de la VGA est bajo slo durante HSYNC_COUNT ciclos a partir del comienzo
  // del barrido de un scanline
  reg hsync_vga, vsync_vga;
    
  always @* begin
    if (addrvga[9:0] < HSYNC_COUNT[9:0])
       hsync_vga = 1'b0;
    else
       hsync_vga = 1'b1;
  end
 
  // El VSYNC de la VGA est bajo slo durante VSYNC_COUNT ciclos a partir del flanco de
  // bajada de la seal de sincronismo vertical original
  reg [15:0] cntvsync = 16'hFFFF;
  initial vsync_vga = 1'b1;
  always @(posedge clk) begin
	 if (clk28en == 1'b1) begin
      if (vsync_ext_n == 1'b0) begin
        if (cntvsync == 16'hFFFF) begin
          cntvsync <= 16'd0;
          vsync_vga <= 1'b0;
        end
        else if (cntvsync != 16'hFFFE) begin
          if (cntvsync == VSYNC_COUNT[15:0]) begin
            vsync_vga <= 1'b1;
            cntvsync <= 16'hFFFE;
          end
          else
            cntvsync <= cntvsync + 16'd1;
        end
      end
      else if (vsync_ext_n == 1'b1)
        cntvsync <= 16'hFFFF;
	 end
  end
  
  // горизонтальный и вертикальный счетчики от начала vga синхры
  reg prev_vsync_vga = 1'b1;
  reg prev_hsync_vga = 1'b1;
  
  always @(posedge clk) begin
		prev_hsync_vga <= hsync_vga;
		// на каждой горизонтальной синхре считаем количество линий, 
		// обнуляем счетчик когда поймали начало вертикальной синхры
		if (prev_hsync_vga == 1'b1 && hsync_vga == 1'b0) begin			
			prev_vsync_vga <= vsync_vga;
			hcnt <= 0;
			if (prev_vsync_vga == 1'b1 && vsync_vga == 1'b0) 
				vcnt <= 0;
			else
				vcnt <= vcnt + 1;
		end
		else
			hcnt <= hcnt + 1;
  end

  always @* begin
    if (enable_scandoubling == 1'b0) begin // 15kHz output
      ro = {ri,ri};
      go = {gi,gi};
      bo = {bi,bi};
      hsync = csync_ext_n;
      vsync = 1'b1;
		//hsync = hsync_ext_n;
		//vsync = vsync_ext_n;
		blank = blanki;
    end
    else begin  // VGA output
      ro = {ro_vga,ro_vga};
      go = {go_vga,go_vga};
      bo = {bo_vga,bo_vga};
      hsync = hsync_vga;
      vsync = vsync_vga;
		//blank = ((hsync_vga == 1'b0) || (vsync_vga == 1'b0));
		blank = blank_h || blank_v;
    end
  end
  
endmodule

// Una memoria de doble puerto: uno para leer, y otro para
// escribir. Es de 2048 direcciones: 1024 se emplean para
// guardar un scan, y otros 1024 para el siguiente scan
module vgascanline_dport (
 input wire clk,
 input wire clk28en,
 input wire [10:0] addrwrite,
 input wire [10:0] addrread,
 input wire we,
 input wire [8:0] din,
 output reg [8:0] dout
 );
 
 reg [8:0] scan[0:2047]; // two scanlines
 always @(posedge clk) begin
	if (clk28en == 1'b1) begin
	  dout <= scan[addrread];
	  if (we == 1'b1)
		scan[addrwrite] <= din;
	end
 end
endmodule

module color_dimmed (
    input wire [2:0] in,
    output reg [2:0] out // out is scaled to roughly 70% of in
    );
    
    always @* begin  // a LUT
        case (in)  
            3'd0 : out = 3'd0;
            3'd1 : out = 3'd1;
            3'd2 : out = 3'd1;
            3'd3 : out = 3'd2;
            3'd4 : out = 3'd3;
            3'd5 : out = 3'd3;
            3'd6 : out = 3'd4;
            3'd7 : out = 3'd5;
            default: out = 3'd0;
        endcase
    end
endmodule
        