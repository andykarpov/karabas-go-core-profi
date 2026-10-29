`timescale 1ns / 1ps
`default_nettype wire

module tb_fdd_virtual;

	// Clock 28 MHz (clk_bus)
	reg clk_bus = 1'b0;
	always #17.857 clk_bus = ~clk_bus;

	// Clock 8 MHz (clk_8)
	reg clk_8 = 1'b0;
	always #62.5 clk_8 = ~clk_8;

	reg reset_bus = 1'b1;
	reg reset_8 = 1'b1;

	// SDC interface
	reg  [1:0]  sdc_img_mounted = 2'b00;
	reg  [63:0] sdc_img_size = 64'd0;
	wire [1:0]  sdc_rd, sdc_wr;
	wire [31:0] sdc_sector;
	reg         sdc_busy = 1'b0;
	reg         sdc_done = 1'b0;
	reg         sdc_error = 1'b0;
	reg         sdc_byte_in_strobe = 1'b0;
	reg  [8:0]  sdc_byte_addr = 9'd0;
	reg  [7:0]  sdc_byte_in_data = 8'd0;
	wire [7:0]  sdc_byte_out_data;

	// FDC drive controls
	reg  [1:0]  fdc_ds = 2'b00;
	reg         fdc_motor = 1'b0;
	reg         fdc_side1 = 1'b0;
	reg         fdc_step = 1'b0;
	reg         fdc_dir = 1'b0;
	reg         fdc_wg = 1'b0;
	reg         fdc_wr_data = 1'b0;

	// Virtual floppy outputs
	wire v_rdata;
	wire v_tr00;
	wire v_index;
	wire v_wprt;
	wire v_active;
	wire led;

	fdd_virtual #(
		.OUT_LATENCY(3)
	) dut (
		.clk_bus(clk_bus),
		.reset_bus(reset_bus),
		.sdc_img_mounted(sdc_img_mounted),
		.sdc_img_size(sdc_img_size),
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

		.clk_8(clk_8),
		.reset_8(reset_8),
		.fdc_ds(fdc_ds),
		.fdc_motor(fdc_motor),
		.fdc_side1(fdc_side1),
		.fdc_step(fdc_step),
		.fdc_dir(fdc_dir),
		.fdc_wg(fdc_wg),
		.fdc_wr_data(fdc_wr_data),

		.v_rdata(v_rdata),
		.v_tr00(v_tr00),
		.v_index(v_index),
		.v_wprt(v_wprt),
		.v_active(v_active),
		.led(led)
	);

	// SD Card emulator responder on clk_bus
	reg [7:0] mock_sd [0:4095]; // 8 sectors of 512 bytes for testing
	integer i;
	initial begin
		for (i = 0; i < 4096; i = i + 1)
			mock_sd[i] = i[7:0] ^ 8'h5A;
	end

	integer sec_cnt = 0;
	integer byte_cnt = 0;

	always @(posedge clk_bus) begin
		sdc_done <= 1'b0;
		sdc_byte_in_strobe <= 1'b0;

		if (!sdc_busy) begin
			if (|sdc_rd) begin
				sdc_busy <= 1'b1;
				byte_cnt <= 0;
			end else if (|sdc_wr) begin
				sdc_busy <= 1'b1;
				byte_cnt <= 0;
			end
		end else begin
			if (byte_cnt < 512) begin
				sdc_byte_addr <= byte_cnt[8:0];
				sdc_byte_in_data <= mock_sd[{sdc_sector[2:0], byte_cnt[8:0]}];
				sdc_byte_in_strobe <= 1'b1;
				byte_cnt <= byte_cnt + 1;
			end else begin
				sdc_busy <= 1'b0;
				sdc_done <= 1'b1;
			end
		end
	end

	// Test sequence
	integer errors = 0;

	initial begin
		$display("--- Starting tb_fdd_virtual ---");

		// 1. Initial reset
		#200;
		reset_bus = 1'b0;
		reset_8 = 1'b0;
		#200;

		if (v_tr00 !== 1'b1) begin
			$display("ERROR: v_tr00 should be 1 at reset!");
			errors = errors + 1;
		end

		// 2. Mount image on DF0 (slot 0)
		sdc_img_mounted = 2'b01;
		sdc_img_size = 64'd655360;
		#500;

		// 3. Select Drive A with motor ON
		fdc_ds = 2'b01;
		fdc_motor = 1'b1;
		#500;

		if (!v_active) begin
			$display("ERROR: v_active should be 1 when DF0 is selected & mounted!");
			errors = errors + 1;
		end

		// 4. Wait for track 0 to load from SD card (8 sectors)
		$display("Waiting for track 0 load from SD card...");
		wait (dut.track_valid == 1'b1);
		$display("Track 0 loaded successfully! (LBA=%0d)", dut.s_state);

		// Verify BRAM contents
		if (dut.track_ram[0] !== (8'h00 ^ 8'h5A)) begin
			$display("ERROR: track_ram[0] mismatch: expected %h, got %h", 8'h00 ^ 8'h5A, dut.track_ram[0]);
			errors = errors + 1;
		end else begin
			$display("Verified track_ram[0] = %h (matches mock SD)", dut.track_ram[0]);
		end

		// 5. Test head stepping
		$display("Testing head step...");
		#1000;
		// Step in (Cyl 0 -> Cyl 1)
		fdc_dir = 1'b1;
		fdc_step = 1'b1;
		#500;
		fdc_step = 1'b0;
		#1000;

		if (dut.cur_cyl !== 7'd1) begin
			$display("ERROR: cur_cyl should be 1 after step in, got %0d", dut.cur_cyl);
			errors = errors + 1;
		end

		if (v_tr00 !== 1'b0) begin
			$display("ERROR: v_tr00 should be 0 at cylinder 1!");
			errors = errors + 1;
		end

		// Step out (Cyl 1 -> Cyl 0)
		fdc_dir = 1'b0;
		fdc_step = 1'b1;
		#500;
		fdc_step = 1'b0;
		#1000;

		if (dut.cur_cyl !== 7'd0) begin
			$display("ERROR: cur_cyl should be 0 after step out, got %0d", dut.cur_cyl);
			errors = errors + 1;
		end

		if (v_tr00 !== 1'b1) begin
			$display("ERROR: v_tr00 should be 1 at cylinder 0!");
			errors = errors + 1;
		end

		// 6. Test MFM read pulses
		$display("Checking MFM pulse stream...");
		// Run for several bit cells, verify v_rdata pulses
		wait (v_rdata == 1'b1);
		$display("SUCCESS: detected v_rdata MFM pulse!");

		// 7. Test MFM Write Path
		$display("Testing MFM Write Path...");
		fdc_wg = 1'b1;
		#1000;

		// Send 3x A1 sync marks (raw 0x4489)
		// 0x4489 = 0100 0100 1000 1001 (16 channel bits)
		repeat(3) begin
			send_mfm_raw(16'h4489);
		end

		// Send Data Mark 0xFB
		// 0xFB = 1111 1011 -> channel bits
		send_mfm_data_byte(8'hFB, 1'b1);

		// Send 256 bytes of data
		for (i = 0; i < 256; i = i + 1) begin
			send_mfm_data_byte(8'hA5, 1'b1);
		end

		#2000;
		fdc_wg = 1'b0;
		#5000;

		if (dut.track_dirty !== 1'b1) begin
			$display("ERROR: track_dirty should be 1 after writing sector!");
			errors = errors + 1;
		end else begin
			$display("SUCCESS: track_dirty asserted, sector captured into BRAM!");
		end

		// 8. Test Track Flush on Step
		$display("Testing Track Flush to SD card on track change...");
		// Step to cylinder 1 (track 2)
		fdc_dir = 1'b1;
		fdc_step = 1'b1;
		#500;
		fdc_step = 1'b0;

		// DUT should flush track 0 (8 sectors via sdc_wr) before loading track 2
		wait (dut.s_state == 3'd1 && dut.bus_is_write == 1'b1);
		$display("SUCCESS: Flush initiated to SD card (LBA=%0d)", dut.sdc_sector);

		wait (dut.track_dirty == 1'b0);
		$display("SUCCESS: Track successfully flushed to SD card, dirty cleared!");

		if (errors == 0)
			$display("=== ALL tb_fdd_virtual TESTS PASSED ===");
		else
			$display("=== FAILED: %0d errors in tb_fdd_virtual ===", errors);

		$finish;
	end

	// Helper tasks for sending MFM bits
	task send_mfm_raw;
		input [15:0] raw;
		integer b;
		begin
			for (b = 15; b >= 0; b = b - 1) begin
				if (raw[b]) begin
					// Pulse in middle of 16-cycle cell
					repeat(7) @(posedge clk_8);
					#10 fdc_wr_data = 1'b1;
					repeat(2) @(posedge clk_8);
					#10 fdc_wr_data = 1'b0;
					repeat(7) @(posedge clk_8);
				end else begin
					repeat(16) @(posedge clk_8);
				end
			end
		end
	endtask

	task send_mfm_data_byte;
		input [7:0] d;
		input       prev;
		reg [15:0] enc;
		begin
			enc = dut.mfm_encode(d, prev);
			send_mfm_raw(enc);
		end
	endtask

endmodule
