`timescale 1ns/1ps
module sram_tb;

reg clk;
reg wr1, rd1, wr2, rd2;
reg [20:0] a1, a2;
reg [7:0] din1, din2;
wire [7:0] dout1, dout2;

wire [20:0] sram_a;
wire [15:0] sram_d;
wire [1:0] sram_wr_n, sram_rd_n;
reg reset;

sram uut(
	.clk(clk),
	.reset(reset),
	
	.port1_a(a1),
	.port1_wr(wr1),
	.port1_rd(rd1),
	.port1_di(din1),
	.port1_do(dout1),
    .port1_ena(1'b1),
	.port1_do_rdy(),

	.port2_a(a2),
	.port2_wr(wr2),
	.port2_rd(rd2),
	.port2_di(din2),
	.port2_do(dout2),
    .port2_ena(1'b1),
	.port2_do_rdy(),
	
	.sram_a(sram_a),
	.sram_d(sram_d),
	.sram_wr_n(sram_wr_n),
	.sram_rd_n(sram_rd_n),

	.busy()
);

sram_model sram_chip1(
    .sram_addr_in(sram_a),
    .sram_data_inout(sram_d[7:0]),
    .we_n(sram_wr_n[0]),
    .oe_n(sram_rd_n[0]),
    .ce_n(sram_rd_n[0] && sram_wr_n[0])
);

sram_model sram_chip2(
    .sram_addr_in(sram_a),
    .sram_data_inout(sram_d[15:8]),
    .we_n(sram_wr_n[1]),
    .oe_n(sram_rd_n[1]),
    .ce_n(sram_rd_n[1] && sram_wr_n[1])
);


initial begin
clk = 0;
reset = 1;
wr1 = 0;
rd1 = 0;
wr2 = 0;
rd2 = 0;
#20;
reset = 0;
#10
din1 = 8'h56;
din2 = 9'h99;
a1 = 55;
a2 = 22;
wr1 = 1;
wr2 = 1;
#20
wr1 = 0;
wr2 = 0;
#20;
#20
#20
a1 = 66;
din1 = 8'h36;
wr1 = 1;
#20
wr1 = 0;
#20
#20
a1 = 55;
rd1 = 1;
#20
rd1 = 0;
#20
#20
a1 = 66;
rd1 = 1;
a2 = 22;
rd2 = 1;
#20
rd1 = 0;
rd2 = 0;
#20
#20
a1 = 55;
rd1 = 1;
#20
rd1 = 0;
#20
#20
#30
#20
#20
#20
$finish();

end

always #10 clk = ~clk;  //clock generation

initial
begin
  $dumpfile("out.vcd");
  $dumpvars(0);

  #1000 $finish;
end

initial
    $monitor($stime,,,, clk,,,, a1,,,, wr1,, rd1,, din1, dout1,,,, sram_a,, sram_wr_n,, sram_rd_n,,,, sram_d);


endmodule

///// sram model

module sram_model
  #(parameter
    SRAM_DATA_WIDTH = 8,
    SRAM_ADDR_WIDTH = 21,

    //timings for 10 ns version
    TAA = 9.9, // address access time 10 ns
    TOHA = 2.5,  //output hold time 2.5 ns
    TACE = 9.9, // ce_n access time
    TDOE = 6.4, // oe_n access time
    THZOE = 3.9, //oe_n to High-Z output
    TLZOE = 0, // oe_n to Low-Z output
    THZCE = 3.9, //ce_n to High-Z output
    TLZCE = 3, // ce_n to Low-Z output
	 THZWE = 4.9, //we_n to High-Z output
    TLZWE = 2 // we_n to Low-Z output
  )
  (
    // inputs
    input wire [SRAM_ADDR_WIDTH - 1: 0] sram_addr_in,
    input wire oe_n,
    input wire ce_n,
    input wire we_n,
    // bidirectional data bus
    inout wire [SRAM_DATA_WIDTH - 1: 0] sram_data_inout
  );
  
  localparam MEMSIZE = 2 ** SRAM_ADDR_WIDTH;
  //---------------------------------------------------------
  //  model of the device
  //
  //  sram_addr_in  +-----------+ mem_data_reg  +-----+ data_out_reg
  //  ------------->| MEM_ARRAY |-------------->|     |------------->
  //        data_in |           |               |     |              
  //        ------->|           |               |     |
  //                +-----------+               |     |   
  //                                            +--+-+|
  //                          z_state_oe ------>| &|1||
  //                          z_state_ce ------>|  | ||
  //                                            +--+ || 
  //                          z_state_we ------>|    ||
  //                                            +--+-+|
  //                       data_valid_oe ------>| &|  |
  //                       data_valid_ce ------>|  |  |
  //                                            +--+--+  
  
  reg [SRAM_DATA_WIDTH - 1: 0] mem_data_reg, data_out_reg;
  
  reg [SRAM_DATA_WIDTH - 1: 0] mem_array[0: MEMSIZE - 1];
  
  reg z_state_oe, z_state_ce, z_state_we, data_valid_oe, data_valid_ce;
  
  initial
  begin
    z_state_oe = 1'b1;
	 z_state_ce = 1'b1; 
	 z_state_we = 1'b0;
	 data_valid_oe = 1'b0;
	 data_valid_ce = 1'b0;
  end
  
  always@(sram_addr_in)
  begin
    #TOHA mem_data_reg = {SRAM_DATA_WIDTH{1'bx}};
	 #(TAA - TOHA) mem_data_reg = mem_array[sram_addr_in];
  end
 
  always@(negedge ce_n)
  begin
    #TLZCE z_state_ce = 1'b0;
  end
  
  always@(negedge ce_n)
  begin
    #TACE data_valid_ce = 1'b1;
  end
  
  always@(negedge oe_n)
  begin
    #TLZOE z_state_oe = 1'b0;
  end
  
  always@(negedge oe_n)
  begin
    #TDOE data_valid_oe = 1'b1;
  end
  
  always@(posedge ce_n)
  begin
    #THZCE z_state_ce = 1'b1;
	 data_valid_ce = 1'b0;
  end
  
  always@(posedge oe_n)
  begin
    #THZOE z_state_oe = 1'b1;
	 data_valid_oe = 1'b0;
  end
  
  always@(negedge we_n)
  begin
    #THZWE z_state_we = 1'b1;
  end
  
  always@(posedge we_n)
  begin
    mem_array[sram_addr_in] = sram_data_inout;
    #TLZWE z_state_we = 1'b0;
  end
  
  wire z_state = z_state_oe || z_state_ce || z_state_we;
  wire data_valid = data_valid_oe && data_valid_ce;
  
  always@*
  begin
    if(z_state)
      data_out_reg = {SRAM_DATA_WIDTH{1'bz}};
	 else if(!data_valid)
	   data_out_reg = {SRAM_DATA_WIDTH{1'bx}};
	 else
	   data_out_reg = mem_data_reg;
  end
  
  assign sram_data_inout = data_out_reg;
endmodule

