//------------------------------------------------------------
// HRDY FDC Top Level
//------------------------------------------------------------
`default_nettype none

module hrdy_fdc (
	// clocks
	input wire         clk,
	input wire         clk_8,
	input wire         reset,

	// cpu signals
	input	wire [15:0] 	a,
	input	wire [7:0]		d,
	input	wire			m1_n,
	input	wire			wr_n,
	input	wire			rd_n,
	input	wire			iorq_n,

	// decoded ports
	input wire          cs_n,
	input wire          csff_n,

	// controller output signals
	output wire         oe_n,
	output wire [7:0]   dout,

	// physical floppy signals
	output wire			FDC_SIDE1,
	input	wire			FDC_RDATA,
	input	wire			FDC_WPRT,
	input	wire			FDC_TR00,
	input	wire			FDC_INDEX,
	output wire			FDC_WG,
	output wire			FDC_WR_DATA,
	output wire			FDC_STEP,
	output wire			FDC_DIR,
	output wire			FDC_MOTOR,
	output wire	[1:0]	FDC_DS
);

/////////////////////////////////////////////////////////////////

// port #FF (TR-DOS) 
reg [7:0] port_ff_reg;
always @(posedge clk) begin
	if (reset)
		port_ff_reg <= 8'b0;
	else if (~csff_n & ~wr_n & ~iorq_n) 
		port_ff_reg <= d;
end

// data out
assign oe_n = ~((~cs_n | ~csff_n) & ~rd_n & ~iorq_n);
assign dout = (~cs_n & ~rd_n) ?  dal : 
				  (~csff_n & ~rd_n) ? {intrq, drq, 6'b111111} : 
				  8'b11111111;


// vg93
wire [7:0] dal = (~wr_n) ? d : 8'bZ;
wire drq, intrq, motor, vfoe, wg, wd, rg, rclk, tr43, early, late, rawread_n;

vg93_top vg93_top(
	.SYSCLK (clk_8),
	.CLK(fdc_clk),
	.MR_n(port_ff_reg[2]),
	
	.CS_n(cs_n),
	.RE_n(rd_n),
	.WE_n(wr_n),
	.A(a[6:5]),
	.DAL(dal),
	.DRQ(drq),
	.INTRQ(intrq),

	.STEP(FDC_STEP),
	.DIRC(FDC_DIR),
	.EARLY(early),
	.LATE(late),
	.HLD(motor),
	.TG43(tr43),
	
	.WG(wg),
	.WD(wd),
	.RG(rg),
	.RCLK(rclk),
	.RAWREAD_n(rawread_n),
	.READY(motor),
	.TR00_n(~FDC_TR00),
	.IP_n(~FDC_INDEX),
	.WPRT_n(~FDC_WPRT),
	.WF_n_VFOE_n(vfoe),
	.HLT(port_ff_reg[3]),
	.TEST_n(1'b1),
	.DDEN_n(1'b0)
);

assign FDC_SIDE1 = ~port_ff_reg[4];
assign FDC_DS[0] = motor & (port_ff_reg[1:0] == 2'b00);
assign FDC_DS[1] = motor & (port_ff_reg[1:0] == 2'b01);
assign FDC_MOTOR = motor;
assign FDC_WG = wg;

// FAPCH
reg [2:0] f;
always @(negedge clk_8) begin
	f <= f+1;
end

wire f4 = f[0]; // write pre-compensation freq

reg f_sel;	
always @(posedge reset, posedge clk_8) begin
	if (reset) 
		f_sel <= 0; // FDC clock (1Mc)				
	else if (FDC_STEP)
		f_sel <= 1; // FDC clock (2Mc)	
	else if (drq)
		f_sel <= 0; // FDC clock (1Mc)
end

// fdc_clk
reg fdc_clk;
reg clk_1m_en, clk_2m_en;

always @(posedge clk_8) begin
    clk_2m_en <= f_sel  & ~f[1];
    clk_1m_en <= ~f_sel & ~f[2];
end

always @(posedge clk_8) begin
    if (clk_2m_en) fdc_clk <= 1'b1;
    else if (clk_1m_en) fdc_clk <= 1'b1;
    else fdc_clk <= 1'b0;
end
	
// RAWR 125 ms
reg [1:0] rd_reg;
always @(posedge clk_8) begin
	rd_reg <= {~rd_reg[0], FDC_RDATA};
end

assign rawread_n = ~(rd_reg[1] & rd_reg[0]);

// FAPCH (calculating RCLK shifts)
reg [4:0] fa;
always @(posedge clk_8) begin
    if (~rawread_n) begin
        // phase correction (lower 4 bits)
        if (fa[3:0] < 3)       fa[3:0] <= fa[3:0] + 4;
        else if (fa[3:0] < 5)  fa[3:0] <= fa[3:0] + 3;
        else if (fa[3:0] < 7)  fa[3:0] <= fa[3:0] + 2;
        else if (fa[3:0] == 7) fa[3:0] <= fa[3:0] + 1;
        else if (fa[3:0] > 12) fa[3:0] <= fa[3:0] - 3;
        else if (fa[3:0] > 9)  fa[3:0] <= fa[3:0] - 2;
        else if (fa[3:0] > 8)  fa[3:0] <= fa[3:0] - 1;
        else                   fa <= fa + 1'b1; // if out of range
    end else begin
        fa <= fa + 1'b1; // if no count pulses
    end
end

assign rclk = ~fa[4];

// Write pre-compensation

reg [3:0] wdata;
always @(posedge clk_8) begin
	if (f4) begin
		if (wd) begin
			wdata[0] <= tr43 & late;
			wdata[1] <= !((tr43 & late) | (tr43 & early));
			wdata[2] <= tr43 & early;
			wdata[3] <= 1'b0;
		end else begin
			wdata <= {wdata[2:0], 1'b0};
		end
	end
end

assign FDC_WR_DATA = wdata[3];

endmodule
