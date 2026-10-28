`timescale 1ns / 1ps
`default_nettype wire

module tb_hdf_ata;

reg clk = 1'b0;
always #17.857 clk = ~clk; // ~28 MHz

reg reset = 1'b1;
reg ata_reset = 1'b0;
reg dev0_en = 1'b1;

wire dev, dev1_here;
reg [2:0] a = 3'd0;
reg [1:0] cs_n = 2'b11;
reg rd_n = 1'b1;
reg wr_n = 1'b1;
reg [15:0] din = 16'd0;
wire [15:0] dout;

reg [1:0] img_mounted = 2'b00;
reg [63:0] img_size = 64'd0;
wire [1:0] sdc_rd, sdc_wr;
wire [31:0] sdc_sector;
reg sdc_busy = 1'b0;
reg sdc_done = 1'b0;
reg sdc_error = 1'b0;
reg sdc_byte_in_strobe = 1'b0;
reg [8:0] sdc_byte_addr = 9'd0;
reg [7:0] sdc_byte_in_data = 8'd0;
wire [7:0] sdc_byte_out_data;
wire led;

hdf_ata #(
	.DEF_HEADS(5'd16),
	.DEF_SPT(8'd63)
) dut (
	.clk(clk),
	.reset(reset),
	.ata_reset(ata_reset),
	.dev0_en(dev0_en),
	.dev(dev),
	.dev1_here(dev1_here),
	.a(a),
	.cs_n(cs_n),
	.rd_n(rd_n),
	.wr_n(wr_n),
	.din(din),
	.dout(dout),
	.img_mounted(img_mounted),
	.img_size(img_size),
	.sdc_rd(sdc_rd),
	.sdc_wr(sdc_wr),
	.sdc_sector(sdc_sector),
	.sdc_busy(sdc_busy),
	.sdc_done(sdc_done),
	.sdc_error(sdc_error),
	.sdc_byte_in_strobe(sdc_byte_in_strobe),
	.sdc_byte_addr(sdc_byte_addr),
	.sdc_byte_in_data(sdc_byte_in_data),
	.sdc_byte_out_data(sdc_byte_out_data),
	.led(led)
);

// Task to write an IDE register
task ide_write;
	input [2:0] reg_a;
	input [1:0] reg_cs;
	input [15:0] data;
	begin
		@(posedge clk);
		a <= reg_a;
		cs_n <= reg_cs;
		din <= data;
		@(posedge clk);
		wr_n <= 1'b0;
		@(posedge clk);
		@(posedge clk);
		@(posedge clk);
		wr_n <= 1'b1;
		@(posedge clk);
		cs_n <= 2'b11;
		@(posedge clk);
	end
endtask

// Task to read an IDE register
task ide_read;
	input [2:0] reg_a;
	input [1:0] reg_cs;
	output [15:0] data;
	begin
		@(posedge clk);
		a <= reg_a;
		cs_n <= reg_cs;
		@(posedge clk);
		rd_n <= 1'b0;
		@(posedge clk);
		@(posedge clk);
		@(posedge clk);
		data = dout;
		rd_n <= 1'b1;
		@(posedge clk);
		cs_n <= 2'b11;
		@(posedge clk);
	end
endtask

// Mock img_sdc response
integer b;
task serve_sdc_read;
	begin
		@(posedge clk);
		sdc_busy <= 1'b1;
		@(posedge clk);
		sdc_busy <= 1'b0;
		for (b = 0; b < 512; b = b + 1) begin
			@(posedge clk);
			sdc_byte_in_strobe <= 1'b1;
			sdc_byte_addr <= b[8:0];
			sdc_byte_in_data <= b[7:0];
		end
		@(posedge clk);
		sdc_byte_in_strobe <= 1'b0;
		@(posedge clk);
		sdc_done <= 1'b1;
		@(posedge clk);
		sdc_done <= 1'b0;
		@(posedge clk);
	end
endtask

reg [15:0] rdata;
integer errors = 0;
integer w;

initial begin
	// Power on reset
	repeat (10) @(posedge clk);
	reset <= 1'b0;
	repeat (10) @(posedge clk);

	$display("tb_hdf_ata: Mounting 10MB image in slot 4 (dev 0)...");
	@(posedge clk);
	img_mounted[0] <= 1'b1;
	img_size <= 64'd10485760; // 10 MB = 20480 sectors
	@(posedge clk);
	img_mounted[0] <= 1'b0;

	// Wait for dut to request sector 0 for geometry
	while (sdc_rd == 2'b00) @(posedge clk);
	$display("tb_hdf_ata: DUT requested sector 0 for geometry");
	serve_sdc_read();

	// Wait for geometry calculation (ST_GEO_DIV) to complete
	repeat (50) @(posedge clk);

	// Read status register (cs0 = cs_n[0]=0, a=7)
	ide_read(3'd7, 2'b10, rdata);
	$display("tb_hdf_ata: Status after mount = 0x%02X (expected 0x50)", rdata[7:0]);
	if (rdata[7:0] !== 8'h50) begin
		$display("ERROR: Status mismatch!");
		errors = errors + 1;
	end

	// Issue IDENTIFY DEVICE (0xEC)
	$display("tb_hdf_ata: Issuing IDENTIFY DEVICE (0xEC)...");
	ide_write(3'd7, 2'b10, 16'h00EC);

	// Wait for DRQ in status
	ide_read(3'd7, 2'b10, rdata);
	while (rdata[3] !== 1'b1) begin // wait DRQ
		@(posedge clk);
		ide_read(3'd7, 2'b10, rdata);
	end
	$display("tb_hdf_ata: DRQ asserted, reading 256 words of IDENTIFY data...");

	// Read 256 words
	for (w = 0; w < 256; w = w + 1) begin
		ide_read(3'd0, 2'b10, rdata);
		if (w == 27 && rdata !== 16'h414B) begin // "KA" (in little-endian: 'K'=0x4B, 'A'=0x41 -> 0x414B or "KA")
			// check ident word
			$display("IDENT word 27 = 0x%04X ('%c%c')", rdata, rdata[15:8], rdata[7:0]);
		end
		if (w == 27) begin
			if (rdata !== "KA" && rdata !== 16'h4B41 && rdata !== 16'h414B) begin
				$display("ERROR: Word 27 model mismatch: 0x%04X", rdata);
				errors = errors + 1;
			end else begin
				$display("tb_hdf_ata: Model string verified successfully");
			end
		end
	end

	// Status after reading all 256 words should be 0x50 (OK, no DRQ)
	ide_read(3'd7, 2'b10, rdata);
	$display("tb_hdf_ata: Status after IDENTIFY = 0x%02X (expected 0x50)", rdata[7:0]);
	if (rdata[7:0] !== 8'h50) begin
		$display("ERROR: Status not OK after IDENTIFY: 0x%02X", rdata[7:0]);
		errors = errors + 1;
	end

	// Test Sector Read (LBA mode)
	$display("tb_hdf_ata: Testing READ SECTORS (LBA 128)...");
	ide_write(3'd2, 2'b10, 16'h0001); // Sector count = 1
	ide_write(3'd3, 2'b10, 16'h0080); // LBA 0-7 = 128
	ide_write(3'd4, 2'b10, 16'h0000); // LBA 8-15 = 0
	ide_write(3'd5, 2'b10, 16'h0000); // LBA 16-23 = 0
	ide_write(3'd6, 2'b10, 16'h00E0); // LBA mode (bit 6=1, bit 4=0 for dev 0)
	ide_write(3'd7, 2'b10, 16'h0020); // READ SECTORS (0x20)

	// Wait for DUT to ask sdc for sector 128
	while (sdc_rd == 2'b00) @(posedge clk);
	$display("tb_hdf_ata: DUT requested sdc_sector = %0d (expected 128)", sdc_sector);
	if (sdc_sector !== 32'd128) begin
		$display("ERROR: sdc_sector mismatch: %0d", sdc_sector);
		errors = errors + 1;
	end

	serve_sdc_read();

	// Wait for DRQ
	ide_read(3'd7, 2'b10, rdata);
	while (rdata[3] !== 1'b1) begin
		@(posedge clk);
		ide_read(3'd7, 2'b10, rdata);
	end

	// Read sector data
	for (w = 0; w < 256; w = w + 1) begin
		ide_read(3'd0, 2'b10, rdata);
		// bytes were: low byte = 2*w, high byte = 2*w+1
		if (rdata[7:0] !== ((2*w) & 8'hFF) || rdata[15:8] !== ((2*w+1) & 8'hFF)) begin
			$display("ERROR: Sector data mismatch at word %0d: 0x%04X", w, rdata);
			errors = errors + 1;
		end
	end

	ide_read(3'd7, 2'b10, rdata);
	$display("tb_hdf_ata: Status after sector read = 0x%02X (expected 0x50)", rdata[7:0]);
	if (rdata[7:0] !== 8'h50) begin
		$display("ERROR: Status not OK after sector read");
		errors = errors + 1;
	end

	$display("tb_hdf_ata: %0d errors", errors);
	if (errors == 0) begin
		$display("TB_HDF_ATA PASSED");
	end else begin
		$display("TB_HDF_ATA FAILED");
	end
	$finish;
end

endmodule
