`timescale 1ns / 1ps
`default_nettype none

//    This file is part of the ZXUNO Spectrum core. 
//    Creation date is 00:52:19 2014-03-04 by Miguel Angel Rodriguez Jodar
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

module zc_spi (
   input wire clk,
	input wire ena,
   input wire tx, // 1 to send byte over SPI
   input wire rx, // 1 to receive byte over SPI
   input wire [7:0] din,
   output reg [7:0] dout,
   output reg oe, // dout is valid
   output reg busy,
   
   output wire spi_clk,    // Interface SPI
   output wire spi_di,     //
   input wire spi_do       //
   );

   reg read_cycle = 1'b0;       		// reading cycle in progress
   reg write_cycle = 1'b0;     		// writing cycle in progress
   reg [4:0] counter = 5'b00000;  	// FSM counter (cycles)
   reg [7:0] data_to_spi;          	// data to be sent to the SPI by DI
   reg [7:0] data_from_spi;        	// data to receive from the SPI
   reg [7:0] data_to_cpu;          	// last data received correctly
   
   assign spi_clk = counter[0];   // spi_clk is half the module clock
   assign spi_di = data_to_spi[7]; // the transmission is from bit 7 to 0
   
   initial busy = 1'b0;
   
   always @(posedge clk) begin
      if (tx && !write_cycle) begin  // if it has been requested, start writing cycle
         write_cycle <= 1'b1;
         read_cycle <= 1'b0;
         counter <= 5'b00000;
         data_to_spi <= din;
         busy <= 1'b1;         
      end
      else if (rx && !read_cycle) begin // if not, check if we need to start the reading cycle.
         read_cycle <= 1'b1;
         write_cycle <= 1'b0;
         counter <= 5'b00000;
         data_to_cpu <= data_from_spi;
         data_from_spi <= 8'h00;
         data_to_spi <= 8'hFF;  // MOSI must be high while reading      
         busy <= 1'b1;
      end
      
      // FSM to send a data to the spi
      else if (write_cycle==1'b1) begin
			if (ena == 1'b1) begin
				if (counter!=5'b10000) begin
					if (counter == 5'b01000)
						 busy <= 1'b0;            
					if (spi_clk==1'b1) begin
						data_to_spi <= {data_to_spi[6:0],1'b0};
						data_from_spi <= {data_from_spi[6:0],spi_do};
					end
					counter <= counter + 1;
				end
				else begin
					if (!tx)
						write_cycle <= 1'b0;
				end
			end
      end
      
      // FSM to read data from the spi
      else if (read_cycle==1'b1) begin
			if (ena == 1'b1) begin
				if (counter!=5'b10000) begin
					if (counter == 5'b01000)
						 busy <= 1'b0;            
					if (spi_clk==1'b1)
						data_from_spi <= {data_from_spi[6:0],spi_do};
					counter <= counter + 1;
				end
				else begin
					if (!rx)
						read_cycle <= 1'b0;
				end
			end
      end
   end
   
	always @* begin
		dout = data_from_spi;
		oe = 1'b1;
	end
	
/*   always @* begin
      if (rx) begin
         dout = data_to_cpu;
         oe = 1'b1;
      end
      else begin
         dout = 8'hZZ;
         oe = 1'b0;
      end
   end*/   
endmodule
