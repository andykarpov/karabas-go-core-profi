//
// sdram.v
//
// sdram controller implementation for the MiST board
// http://code.google.com/p/mist-board/
// 
// Copyright (c) 2013 Till Harbaum <till@harbaum.org> 
// 
// This source file is free software: you can redistribute it and/or modify 
// it under the terms of the GNU General Public License as published 
// by the Free Software Foundation, either version 3 of the License, or 
// (at your option) any later version. 
// 
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of 
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the 
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License 
// along with this program.  If not, see <http://www.gnu.org/licenses/>. 
//

module sdram (

	// interface to the MT48LC16M16 chip
	inout wire [15:0]    sd_data,    // 16 bit bidirectional data bus
	output reg [12:0]   sd_addr,    // 13 bit multiplexed address bus
	output reg [1:0]    sd_dqm,     // two byte masks
	output reg [1:0]    sd_ba,      // two banks
	output wire         sd_cs,      // a single chip select
	output wire         sd_we,      // write enable
	output wire         sd_ras,     // row address select
	output wire         sd_cas,     // columns address select
	output wire         sd_clk,	  // clock

	// cpu/chipset interface
	input wire          init,			// init signal after FPGA config to initialize RAM
	input wire          clk,			// sdram is accessed at up to 128MHz
	
	input wire [7:0]    din,			// data input from chipset/cpu
	output reg [7:0]    dout,       // data output to chipset/cpu
	input wire [24:0]   addr,       // 25 bit byte address
	input wire          oe,         // cpu/chipset requests read
	input wire          we,         // cpu/chipset requests write
	output reg          busy        // chip busy 
);

// no burst configured
localparam RASCAS_DELAY   = 3'd3;   // tRCD>=20ns -> 3 cycles@112MHz
localparam BURST_LENGTH   = 3'b000; // 000=none, 001=2, 010=4, 011=8
localparam ACCESS_TYPE    = 1'b0;   // 0=sequential, 1=interleaved
localparam CAS_LATENCY    = 3'd3;   // 2/3 allowed
localparam OP_MODE        = 2'b00;  // only 00 (standard operation) allowed
localparam NO_WRITE_BURST = 1'b1;   // 0= write burst enabled, 1=only single access write

localparam MODE = { 3'b000, NO_WRITE_BURST, OP_MODE, CAS_LATENCY, ACCESS_TYPE, BURST_LENGTH}; 

// ---------------------------------------------------------------------
// ------------------------ cycle state machine ------------------------
// ---------------------------------------------------------------------

localparam STATE_IDLE      = 3'd0;   // first state in cycle
localparam STATE_CMD_CONT  = STATE_IDLE + RASCAS_DELAY; // 2 command can be continued
localparam STATE_CMD_READ  = STATE_CMD_CONT + CAS_LATENCY + 1'd1; // 5
localparam STATE_LAST      = 3'd5;   // last state in cycle

reg [2:0] q;
always @(posedge clk) begin
	q <= q + 1'd1;
	if (q == STATE_LAST) q <= 0;
end

// ---------------------------------------------------------------------
// --------------------------- startup/reset ---------------------------
// ---------------------------------------------------------------------

// wait 1ms (32 clkref cycles) after FPGA config is done before going
// into normal operation. Initialize the ram in the last 16 reset cycles (cycles 15-0)
reg [4:0] reset;
always @(posedge clk, posedge init) begin
	if(init)	reset <= 5'h1f;
	else if((q == STATE_LAST) && (reset != 0))
		reset <= reset - 5'd1;
end

// ---------------------------------------------------------------------
// ------------------ generate ram control signals ---------------------
// ---------------------------------------------------------------------

// all possible commands
localparam CMD_INHIBIT         = 4'b1111;
localparam CMD_NOP             = 4'b0111;
localparam CMD_ACTIVE          = 4'b0011;
localparam CMD_READ            = 4'b0101;
localparam CMD_WRITE           = 4'b0100;
localparam CMD_BURST_TERMINATE = 4'b0110;
localparam CMD_PRECHARGE       = 4'b0010;
localparam CMD_AUTO_REFRESH    = 4'b0001;
localparam CMD_LOAD_MODE       = 4'b0000;

reg [3:0] sd_cmd;   // current command sent to sd ram

// drive control signals according to current command
assign sd_cs  = sd_cmd[3];
assign sd_ras = sd_cmd[2];
assign sd_cas = sd_cmd[1];
assign sd_we  = sd_cmd[0];

wire [12:0] reset_addr = (reset == 13)?13'b0010000000000:MODE;
reg oe_latch, we_latch;
reg oe_old, we_old;
wire oe_next = ~oe_old & oe;
wire we_next = ~we_old & we;
reg [15:0] sd_data_r;
assign sd_data = sd_data_r;

always @(posedge clk) begin
	sd_cmd <= CMD_INHIBIT;
	sd_data_r <= 16'bZZZZZZZZZZZZZZZZ;

	if(reset != 0) begin
		busy <= 1'b1;
		{oe_latch, we_latch} <= 0;
		sd_dqm <= 2'b11;
		sd_addr <= reset_addr;
		if(q == STATE_IDLE) begin
			if(reset == 13)  sd_cmd <= CMD_PRECHARGE;
			if(reset ==  2)  sd_cmd <= CMD_LOAD_MODE;
		end
	end else begin
		sd_dqm <= 2'b00;
		if(q == STATE_IDLE) begin
			busy <= 1'b0;
			oe_old <= oe;
			we_old <= we;
			{oe_latch, we_latch} <= {oe_next, we_next};
			if(we_next || oe_next) begin
				busy <= 1'b1;
				sd_cmd <= CMD_ACTIVE;
				sd_addr <= addr[21:9];
				sd_ba <= addr[23:22];
			end
			else begin
				busy <= 1'b1;
				sd_cmd <= CMD_AUTO_REFRESH;
			end
		end else if(q == STATE_CMD_CONT) begin
			busy <= 1'b1;
			if(we_latch || oe_latch) sd_addr <= { 4'b0010, addr[8:0]};
			if(we_latch) begin
				sd_cmd <= CMD_WRITE;
				sd_data_r <= {din, din};
			end
			else if(oe_latch) sd_cmd <= CMD_READ;
		end else if(q == STATE_CMD_READ) begin
			busy <= 1'b0;
			if(oe_latch) dout <= sd_data[7:0];
		end
	end
end

//ODDR2 clkbuf(.Q(sd_clk), .C0(clk), .C1(~clk), .CE(1'b1), .D0(1'b0), .D1(1'b1), .R(1'b0), .S(1'b0));

wire sd_clk_ddr;
ODDR2 #(
        .DDR_ALIGNMENT("NONE"),
        .INIT(1'b0),
        .SRTYPE("SYNC")
    ) ODDR2_inst (
        .Q(sd_clk_ddr), // 1-bit DDR output data
        .C0(clk), // 1-bit clock input
        .C1(~clk), // 1-bit clock input
        .CE(1'b1), // 1-bit clock enable input
        .D0(1'b0), // 1-bit data input (associated with C0)
        .D1(1'b1), // 1-bit data input (associated with C1)
        .R(1'b0), // 1-bit reset input
        .S(1'b0) // 1-bit set input
    );

IODELAY2 #(
        .IDELAY_VALUE(0),
        .IDELAY_MODE("NORMAL"),
        .ODELAY_VALUE(100), // value of 100 seems to work at 100MHz
        .IDELAY_TYPE("FIXED"),
        .DELAY_SRC("ODATAIN"),
        .DATA_RATE("SDR")
    ) IODELAY_inst (
        .IDATAIN(1'b0),
        .T(1'b0),
        .ODATAIN(sd_clk_ddr),
        .CAL(1'b0),
        .IOCLK0(1'b0),
        .IOCLK1(1'b0),
        .CLK(1'b0),
        .INC(1'b0),
        .CE(1'b0),
        .RST(1'b0),
        .BUSY(),
        .DATAOUT(),
        .DATAOUT2(),
        .TOUT(),
        .DOUT(sd_clk)
    );

endmodule
