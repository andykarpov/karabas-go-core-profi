`default_nettype none
/*
  -----------------------------------------------------------------------------
   General Sound for Karabas Go
  -----------------------------------------------------------------------------
*/
module gs_top (
    // clocks
    input wire            clk_bus,
    input wire            ce,
    input wire            reset,
    input wire            areset,
	 input wire            ds80,

    // cpu input signals
    input wire [15:0]      a,
    input wire [7:0]       di,
    input wire            mreq_n,
    input wire            iorq_n,
    input wire            m1_n,
    input wire            rd_n,
    input wire            wr_n,

    // data out to cpu
    output wire           oe,
    output wire [7:0]     do_bus,

	output wire [20:0] 	 sram_a,
	output wire 			 sram_rd,
	output wire 			 sram_wr,
	output wire [7:0]		 sram_di,
	input wire [7:0] 		 sram_do,

    // sound output
	output wire signed [14:0] out_l,
	output wire signed [14:0] out_r

);

// gs

wire [20:0] gs_mem_addr;
wire  [7:0] gs_mem_dout;
wire  [7:0] gs_mem_din;
wire        gs_mem_rd_n;
wire        gs_mem_wr_n;

gs gs 
(
    .RESET(reset),
    .CLK(clk_bus),
    .CE(ce), 
	 .DS80(ds80),
    
    .A(a),
    .DI(di),
    .DO(do_bus),
    .OE(oe),
    .WR_n(wr_n),
    .RD_n(rd_n),
    .IORQ_n(iorq_n),
    .M1_n(m1_n),

    .OUT_L(out_l),
    .OUT_R(out_r),

    .MA(gs_mem_addr),
    .MDI(gs_mem_din),
    .MDO(gs_mem_dout),
    .MRFSH_n(),
    .MWE_n(gs_mem_wr_n),
    .MRD_n(gs_mem_rd_n)
);

// sram
assign sram_wr = ~gs_mem_wr_n;
assign sram_rd = ~gs_mem_rd_n;
assign sram_a = gs_mem_addr;
assign sram_di = gs_mem_dout;
assign gs_mem_din = sram_do; 

endmodule
