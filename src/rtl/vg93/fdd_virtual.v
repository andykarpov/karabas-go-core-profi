`timescale 1ns / 1ps
`default_nettype wire

/*
 fdd_virtual.v

 Honest MFM floppy emulation for Karabas-Go / Profi core.
 Emulates TR-DOS Double Density floppy drives (DF0 / DF1) on .trd images from SD card via img_sdc.

 Geometry:
 - 80 cylinders, 2 heads = 160 tracks (0..159).
 - 16 sectors per track, 256 bytes per sector = 4096 bytes (4 KB) per track.
 - 8 SD card sectors (512 bytes) per track: LBA = (cylinder * 2 + head) * 8.
 - Dual-port 4 KB BRAM track buffer (2 Block RAMs, RAMB16BWER x 2):
   - Port A: clk_bus (28 MHz) - SD card sector read/write via img_sdc.
   - Port B: clk_8 (8 MHz) - MFM serializer and write receiver.

 MFM Read Path:
 - 300 RPM = 200 ms per revolution (1,600,000 clocks of clk_8).
 - 250 kbps data rate, 4 us bit cell (32 clocks of clk_8), 2 us half-cell (16 clocks).
 - Standard IBM System 34 / TR-DOS track layout (Gap 1, 16 sectors with Address Mark 0xFE,
   sync 3x 0xA1 (raw 0x4489), 256 data bytes, Data Mark 0xFB, CRC16-CCITT 0x1021).
 - Generates 125 ns active-high pulses on v_rdata into hrdy_fdc digital PLL and vg93_top.

 MFM Write Path:
 - When fdc_wg is active: samples fdc_wr_data, synchronizes to 0xA1 marks,
   captures 256 bytes for sector Data Mark 0xFB, writes into BRAM and marks track dirty.
 - Flushes dirty track back to SD card when track changes, motor turns off, or after inactivity.
*/

module fdd_virtual #(
	parameter OUT_LATENCY = 3
) (
	// Clock domain A: clk_bus (28 MHz) - SD Card sector transfer via img_sdc
	input  wire        clk_bus,
	input  wire        reset_bus,

	// Interface to img_sdc (slots 0 and 1: DF0 and DF1)
	input  wire [1:0]  sdc_img_mounted,    // [0] DF0, [1] DF1
	input  wire [63:0] sdc_img_size,
	output reg  [1:0]  sdc_rd = 2'b00,
	output reg  [1:0]  sdc_wr = 2'b00,
	output reg  [31:0] sdc_sector = 32'd0,
	input  wire        sdc_busy,
	input  wire        sdc_done,
	input  wire        sdc_error,
	input  wire        sdc_byte_in_strobe,
	input  wire [8:0]  sdc_byte_addr,
	input  wire [7:0]  sdc_byte_in_data,
	output wire [7:0]  sdc_byte_out_data,

	// Clock domain B: clk_8 (8 MHz) - FDC / MFM
	input  wire        clk_8,
	input  wire        reset_8,

	// Drive control from hrdy_fdc / port #FF
	input  wire [1:0]  fdc_ds,             // drive select (bit 0 = drive A, bit 1 = drive B)
	input  wire        fdc_motor,          // motor on
	input  wire        fdc_side1,          // side select (0 = side 0, 1 = side 1)
	input  wire        fdc_step,           // step pulse
	input  wire        fdc_dir,            // step direction (1 = step in, 0 = step out)
	input  wire        fdc_wg,             // write gate
	input  wire        fdc_wr_data,        // write data pulse

	// Emulated floppy outputs to hrdy_fdc
	output wire        v_rdata,            // read data pulse (125 ns active high)
	output wire        v_tr00,             // track 0 sensor (active high)
	output wire        v_index,            // index pulse (active high)
	output wire        v_wprt,             // write protect (active high)
	output wire        v_active,           // virtual drive currently selected & active

	output wire        led                 // disk activity LED
);

	// =========================================================================
	// 1. Dual-Port 4096-Byte Track RAM (2x RAMB16BWER)
	// =========================================================================
	reg [7:0] track_ram [0:4095];

	// Port A (clk_bus)
	reg [11:0] ram_a_addr = 12'd0;
	reg        ram_a_we = 1'b0;
	reg [7:0]  ram_a_din = 8'd0;
	reg [7:0]  ram_a_dout = 8'd0;

	always @(posedge clk_bus) begin
		if (ram_a_we)
			track_ram[ram_a_addr] <= ram_a_din;
		ram_a_dout <= track_ram[ram_a_addr];
	end

	// Output pipeline for OUT_LATENCY = 3:
	// sdc_byte_addr -> ram_a_addr (clock 1) -> ram_a_dout (clock 2) -> pipe (clock 3)
	reg [7:0] sdc_out_pipe = 8'd0;
	always @(posedge clk_bus) begin
		sdc_out_pipe <= ram_a_dout;
	end
	assign sdc_byte_out_data = sdc_out_pipe;

	// Port B (clk_8)
	reg [11:0] ram_b_addr = 12'd0;
	reg        ram_b_we = 1'b0;
	reg [7:0]  ram_b_din = 8'd0;
	reg [7:0]  ram_b_dout = 8'd0;

	always @(posedge clk_8) begin
		if (ram_b_we)
			track_ram[ram_b_addr] <= ram_b_din;
		ram_b_dout <= track_ram[ram_b_addr];
	end

	// =========================================================================
	// 2. Drive Selection & Head Tracking (clk_8)
	// =========================================================================
	// Synchronize mounted signals from clk_bus to clk_8
	reg [1:0] mnt_meta = 2'b00, mnt_sync = 2'b00;
	always @(posedge clk_8) begin
		mnt_meta <= sdc_img_mounted;
		mnt_sync <= mnt_meta;
	end

	wire sel_drv0 = fdc_ds[0];
	wire sel_drv1 = fdc_ds[1];
	wire cur_drv = sel_drv1; // 0 = drive A, 1 = drive B
	wire drv_mounted = cur_drv ? mnt_sync[1] : mnt_sync[0];

	// Active when a drive is selected, motor is on, and an image is mounted
	assign v_active = fdc_motor && ((sel_drv0 && mnt_sync[0]) || (sel_drv1 && mnt_sync[1]));

	reg [6:0] cyl [0:1]; // Cylinder 0..79 for drive 0 and drive 1
	reg fdc_step_d = 1'b0;

	always @(posedge clk_8) begin
		if (reset_8) begin
			cyl[0] <= 7'd0;
			cyl[1] <= 7'd0;
			fdc_step_d <= 1'b0;
		end else begin
			fdc_step_d <= fdc_step;
			if (fdc_step && !fdc_step_d) begin
				if (sel_drv0) begin
					if (fdc_dir) begin
						if (cyl[0] < 7'd79) cyl[0] <= cyl[0] + 7'd1;
					end else begin
						if (cyl[0] > 7'd0)  cyl[0] <= cyl[0] - 7'd1;
					end
				end else if (sel_drv1) begin
					if (fdc_dir) begin
						if (cyl[1] < 7'd79) cyl[1] <= cyl[1] + 7'd1;
					end else begin
						if (cyl[1] > 7'd0)  cyl[1] <= cyl[1] - 7'd1;
					end
				end
			end
		end
	end

	wire [6:0] cur_cyl = cur_drv ? cyl[1] : cyl[0];
	wire [7:0] target_track = {cur_cyl, fdc_side1}; // 0..159

	assign v_tr00 = (cur_cyl == 7'd0);
	assign v_wprt = 1'b0; // write enabled

	// =========================================================================
	// 3. Track Cache Management & CDC (clk_8 <-> clk_bus)
	// =========================================================================
	// Stepping settle timer: wait ~1 ms (8000 clocks of 8 MHz) after step before loading
	reg [13:0] settle_cnt = 14'd0;
	reg settle_done = 1'b1;

	always @(posedge clk_8) begin
		if (reset_8 || (fdc_step && !fdc_step_d)) begin
			settle_cnt <= 14'd0;
			settle_done <= 1'b0;
		end else if (!settle_done) begin
			if (settle_cnt == 14'd8000)
				settle_done <= 1'b1;
			else
				settle_cnt <= settle_cnt + 14'd1;
		end
	end

	// Track cache state
	reg [7:0] loaded_track = 8'hFF;
	reg       loaded_drv = 1'b0;
	reg       track_valid = 1'b0;
	reg       track_dirty = 1'b0;

	// Inactivity timer for flushing dirty track (~1 second = 8,000,000 clocks)
	reg [23:0] inact_cnt = 24'd0;
	reg inact_flush = 1'b0;

	always @(posedge clk_8) begin
		if (reset_8 || fdc_wg) begin
			inact_cnt <= 24'd0;
			inact_flush <= 1'b0;
		end else if (track_dirty) begin
			if (inact_cnt >= 24'd8000000)
				inact_flush <= 1'b1;
			else
				inact_cnt <= inact_cnt + 24'd1;
		end else begin
			inact_cnt <= 24'd0;
			inact_flush <= 1'b0;
		end
	end

	// CDC Handshake registers (clk_8 domain)
	reg cmd_req = 1'b0;
	reg cmd_is_write = 1'b0;
	reg [7:0] cmd_track = 8'd0;
	reg cmd_drv = 1'b0;

	// Synchronize ack from clk_bus to clk_8
	reg ack_meta = 1'b0, ack_sync = 1'b0, ack_prev = 1'b0;
	always @(posedge clk_8) begin
		ack_meta <= bus_ack;
		ack_sync <= ack_meta;
		ack_prev <= ack_sync;
	end
	wire bus_done_pulse = (ack_sync != ack_prev);

	// State machine on clk_8 for cache coordination
	localparam CM_IDLE  = 2'd0;
	localparam CM_FLUSH = 2'd1;
	localparam CM_LOAD  = 2'd2;
	localparam CM_WAIT  = 2'd3;

	reg [1:0] cm_state = CM_IDLE;
	reg [1:0] cm_next = CM_IDLE;

	wire need_track = v_active && settle_done &&
	                  (!track_valid || target_track != loaded_track || cur_drv != loaded_drv);

	always @(posedge clk_8) begin
		if (reset_8) begin
			cm_state <= CM_IDLE;
			track_valid <= 1'b0;
			track_dirty <= 1'b0;
			loaded_track <= 8'hFF;
			cmd_req <= 1'b0;
		end else begin
			// Mark dirty when a sector write succeeds
			if (wr_dirty_pulse)
				track_dirty <= 1'b1;

			case (cm_state)
				CM_IDLE: begin
					if (need_track) begin
						if (track_dirty) begin
							// Must flush old track first
							cmd_is_write <= 1'b1;
							cmd_track <= loaded_track;
							cmd_drv <= loaded_drv;
							cmd_req <= ~cmd_req;
							cm_next <= CM_LOAD;
							cm_state <= CM_WAIT;
						end else begin
							// Directly load new track
							cmd_is_write <= 1'b0;
							cmd_track <= target_track;
							cmd_drv <= cur_drv;
							cmd_req <= ~cmd_req;
							cm_next <= CM_IDLE;
							cm_state <= CM_WAIT;
						end
					end else if ((inact_flush || (!fdc_motor && track_dirty)) && track_dirty) begin
						// Flush dirty track on inactivity or motor off
						cmd_is_write <= 1'b1;
						cmd_track <= loaded_track;
						cmd_drv <= loaded_drv;
						cmd_req <= ~cmd_req;
						cm_next <= CM_IDLE;
						cm_state <= CM_WAIT;
					end
				end

				CM_WAIT: begin
					if (bus_done_pulse) begin
						if (cmd_is_write) begin
							track_dirty <= 1'b0;
							if (cm_next == CM_LOAD) begin
								// Now load target track
								cmd_is_write <= 1'b0;
								cmd_track <= target_track;
								cmd_drv <= cur_drv;
								cmd_req <= ~cmd_req;
								cm_next <= CM_IDLE;
								cm_state <= CM_WAIT;
							end else begin
								cm_state <= CM_IDLE;
							end
						end else begin
							// Load completed
							track_valid <= 1'b1;
							track_dirty <= 1'b0;
							loaded_track <= cmd_track;
							loaded_drv <= cmd_drv;
							cm_state <= CM_IDLE;
						end
					end
				end

				default: cm_state <= CM_IDLE;
			endcase
		end
	end

	// =========================================================================
	// 4. SD Card Sector Engine (clk_bus)
	// =========================================================================
	// Synchronize cmd_req from clk_8 to clk_bus
	reg req_meta = 1'b0, req_sync = 1'b0, req_prev = 1'b0;
	reg bus_ack = 1'b0;

	always @(posedge clk_bus) begin
		req_meta <= cmd_req;
		req_sync <= req_meta;
		req_prev <= req_sync;
	end
	wire cmd_start = (req_sync != req_prev);

	localparam S_IDLE  = 3'd0;
	localparam S_REQ   = 3'd1;
	localparam S_WAIT  = 3'd2;
	localparam S_NEXT  = 3'd3;
	localparam S_DONE  = 3'd4;

	reg [2:0] s_state = S_IDLE;
	reg [2:0] sub_sec = 3'd0;
	reg bus_is_write = 1'b0;
	reg [7:0] bus_track = 8'd0;
	reg bus_drv = 1'b0;

	always @(posedge clk_bus) begin
		ram_a_we <= 1'b0;
		if (reset_bus) begin
			s_state <= S_IDLE;
			sdc_rd <= 2'b00;
			sdc_wr <= 2'b00;
			bus_ack <= 1'b0;
		end else case (s_state)
			S_IDLE: begin
				if (cmd_start) begin
					bus_is_write <= cmd_is_write;
					bus_track <= cmd_track;
					bus_drv <= cmd_drv;
					sub_sec <= 3'd0;
					s_state <= S_REQ;
				end
			end

			S_REQ: begin
				sdc_sector <= {21'd0, bus_track, sub_sec};
				if (bus_is_write)
					sdc_wr[bus_drv] <= 1'b1;
				else
					sdc_rd[bus_drv] <= 1'b1;

				if (sdc_busy) begin
					sdc_rd <= 2'b00;
					sdc_wr <= 2'b00;
					s_state <= S_WAIT;
				end
			end

			S_WAIT: begin
				if (!bus_is_write) begin
					// Read: incoming bytes into BRAM
					if (sdc_byte_in_strobe) begin
						ram_a_we <= 1'b1;
						ram_a_addr <= {sub_sec, sdc_byte_addr};
						ram_a_din <= sdc_byte_in_data;
					end
				end else begin
					// Write: read address into BRAM
					ram_a_addr <= {sub_sec, sdc_byte_addr};
				end

				if (sdc_done) begin
					s_state <= S_NEXT;
				end
			end

			S_NEXT: begin
				if (sub_sec < 3'd7) begin
					sub_sec <= sub_sec + 3'd1;
					s_state <= S_REQ;
				end else begin
					s_state <= S_DONE;
				end
			end

			S_DONE: begin
				bus_ack <= ~bus_ack;
				s_state <= S_IDLE;
			end

			default: s_state <= S_IDLE;
		endcase
	end

	// Activity LED
	assign led = (s_state != S_IDLE) || (cm_state != CM_IDLE);

	// =========================================================================
	// 5. CRC-16 CCITT Function (0x1021)
	// =========================================================================
	function [15:0] crc16_byte;
		input [15:0] c;
		input [7:0]  d;
		reg   [15:0] nc;
	begin
		nc[ 0] = c[12] ^ c[8] ^ d[0] ^ d[4];
		nc[ 1] = c[13] ^ c[9] ^ d[1] ^ d[5];
		nc[ 2] = c[10] ^ c[14] ^ d[2] ^ d[6];
		nc[ 3] = c[11] ^ c[15] ^ d[3] ^ d[7];
		nc[ 4] = c[12] ^ d[4];
		nc[ 5] = c[12] ^ c[13] ^ c[8] ^ d[0] ^ d[4] ^ d[5];
		nc[ 6] = c[13] ^ c[14] ^ c[9] ^ d[1] ^ d[5] ^ d[6];
		nc[ 7] = c[10] ^ c[14] ^ c[15] ^ d[2] ^ d[6] ^ d[7];
		nc[ 8] = c[0] ^ c[11] ^ c[15] ^ d[3] ^ d[7];
		nc[ 9] = c[1] ^ c[12] ^ d[4];
		nc[10] = c[13] ^ c[2] ^ d[5];
		nc[11] = c[14] ^ c[3] ^ d[6];
		nc[12] = c[12] ^ c[15] ^ c[4] ^ c[8] ^ d[0] ^ d[4] ^ d[7];
		nc[13] = c[13] ^ c[5] ^ c[9] ^ d[1] ^ d[5];
		nc[14] = c[10] ^ c[14] ^ c[6] ^ d[2] ^ d[6];
		nc[15] = c[11] ^ c[15] ^ c[7] ^ d[3] ^ d[7];
		crc16_byte = nc;
	end
	endfunction

	// =========================================================================
	// 6. MFM Channel Encoding Function
	// =========================================================================
	function [15:0] mfm_encode;
		input [7:0] d;
		input       prev_bit;
		reg   [7:0] c;
	begin
		c[7] = (~d[7]) & (~prev_bit);
		c[6] = (~d[6]) & (~d[7]);
		c[5] = (~d[5]) & (~d[6]);
		c[4] = (~d[4]) & (~d[5]);
		c[3] = (~d[3]) & (~d[4]);
		c[2] = (~d[2]) & (~d[3]);
		c[1] = (~d[1]) & (~d[2]);
		c[0] = (~d[0]) & (~d[1]);
		mfm_encode = {
			c[7], d[7], c[6], d[6], c[5], d[5], c[4], d[4],
			c[3], d[3], c[2], d[2], c[1], d[1], c[0], d[0]
		};
	end
	endfunction

	// =========================================================================
	// 7. MFM Serializer (clk_8)
	// =========================================================================
	// Timing:
	// - 1 channel bit = 16 clocks (2 us)
	// - 1 byte = 16 channel bits = 256 clocks (32 us)
	// - 1 revolution = 6250 bytes = 1,600,000 clocks (200 ms, 300 RPM)
	reg [7:0]  byte_clk_cnt = 8'd0;
	reg [12:0] track_byte_cnt = 13'd0;
	reg [3:0]  sec_idx = 4'd0;
	reg [8:0]  byte_in_sec = 9'd0;

	// 4 ms Index pulse at start of revolution (125 bytes * 32 us = 4000 us = 4 ms)
	assign v_index = (track_byte_cnt < 13'd125);

	// Byte selector for standard TR-DOS track:
	// - Gap 1: bytes 0..79 (80 bytes of 0x4E)
	// - 16 Sectors: bytes 80..6031 (372 bytes each)
	// - Gap 4: bytes 6032..6249 (218 bytes of 0x4E)
	reg [7:0]  tx_byte;
	reg        tx_is_sync;
	reg [15:0] crc_reg = 16'hFFFF;

	always @(*) begin
		tx_byte = 8'h4E;
		tx_is_sync = 1'b0;

		if (!track_valid) begin
			tx_byte = 8'h4E; // output gaps while track is not ready
		end else if (track_byte_cnt < 13'd80) begin
			tx_byte = 8'h4E; // Gap 1
		end else if (track_byte_cnt >= 13'd6032) begin
			tx_byte = 8'h4E; // Gap 4
		end else begin
			// Within 16 sectors
			case (byte_in_sec)
				// ID Preamble: 12 bytes 0x00
				9'd0, 9'd1, 9'd2, 9'd3, 9'd4, 9'd5,
				9'd6, 9'd7, 9'd8, 9'd9, 9'd10, 9'd11: tx_byte = 8'h00;

				// ID Sync: 3 bytes 0xA1
				9'd12, 9'd13, 9'd14: begin
					tx_byte = 8'hA1;
					tx_is_sync = 1'b1;
				end

				// Address Mark & Header
				9'd15: tx_byte = 8'hFE;                     // Address Mark
				9'd16: tx_byte = {1'b0, cur_cyl};           // Cylinder C
				9'd17: tx_byte = {7'd0, fdc_side1};         // Head H
				9'd18: tx_byte = {4'd0, sec_idx} + 8'd1;    // Sector R (1..16)
				9'd19: tx_byte = 8'h01;                     // Length N = 1 (256 bytes)
				9'd20: tx_byte = crc_reg[15:8];             // CRC MSB
				9'd21: tx_byte = crc_reg[7:0];              // CRC LSB

				// Gap 2: 22 bytes 0x4E
				9'd22, 9'd23, 9'd24, 9'd25, 9'd26, 9'd27, 9'd28, 9'd29,
				9'd30, 9'd31, 9'd32, 9'd33, 9'd34, 9'd35, 9'd36, 9'd37,
				9'd38, 9'd39, 9'd40, 9'd41, 9'd42, 9'd43: tx_byte = 8'h4E;

				// Data Preamble: 12 bytes 0x00
				9'd44, 9'd45, 9'd46, 9'd47, 9'd48, 9'd49,
				9'd50, 9'd51, 9'd52, 9'd53, 9'd54, 9'd55: tx_byte = 8'h00;

				// Data Sync: 3 bytes 0xA1
				9'd56, 9'd57, 9'd58: begin
					tx_byte = 8'hA1;
					tx_is_sync = 1'b1;
				end

				// Data Mark
				9'd59: tx_byte = 8'hFB;

				// Data bytes (60..315): from BRAM
				default: begin
					if (byte_in_sec >= 9'd60 && byte_in_sec <= 9'd315)
						tx_byte = ram_b_dout;
					else if (byte_in_sec == 9'd316)
						tx_byte = crc_reg[15:8]; // Data CRC MSB
					else if (byte_in_sec == 9'd317)
						tx_byte = crc_reg[7:0];  // Data CRC LSB
					else
						tx_byte = 8'h4E;         // Gap 3 (318..371): 54 bytes 0x4E
				end
			endcase
		end
	end

	// Pre-fetch BRAM address for Port B
	always @(*) begin
		if (byte_in_sec >= 9'd59 && byte_in_sec <= 9'd314)
			ram_b_addr = {sec_idx, (byte_in_sec[7:0] - 8'd59)};
		else if (wr_active)
			ram_b_addr = {wr_sec, wr_byte_cnt};
		else
			ram_b_addr = 12'd0;
	end

	// Advance serializer & CRC
	reg [15:0] ch_word = 16'hAAAA;
	reg prev_data_bit = 1'b0;

	always @(posedge clk_8) begin
		if (reset_8) begin
			byte_clk_cnt <= 8'd0;
			track_byte_cnt <= 13'd0;
			sec_idx <= 4'd0;
			byte_in_sec <= 9'd0;
			ch_word <= 16'hAAAA;
			prev_data_bit <= 1'b0;
			crc_reg <= 16'hFFFF;
		end else begin
			byte_clk_cnt <= byte_clk_cnt + 8'd1;

			if (byte_clk_cnt == 8'd255) begin
				// Track position counter
				if (track_byte_cnt == 13'd6249) begin
					track_byte_cnt <= 13'd0;
					sec_idx <= 4'd0;
					byte_in_sec <= 9'd0;
				end else begin
					track_byte_cnt <= track_byte_cnt + 13'd1;
					if (track_byte_cnt >= 13'd79 && track_byte_cnt < 13'd6031) begin
						if (byte_in_sec == 9'd371) begin
							byte_in_sec <= 9'd0;
							sec_idx <= sec_idx + 4'd1;
						end else begin
							byte_in_sec <= byte_in_sec + 9'd1;
						end
					end
				end

				// Update CRC
				if (byte_in_sec == 9'd14 || byte_in_sec == 9'd58) begin
					crc_reg <= 16'hcdb4; // Preset after 3x A1 sync
				end else if ((byte_in_sec >= 9'd15 && byte_in_sec <= 9'd19) ||
				             (byte_in_sec >= 9'd59 && byte_in_sec <= 9'd315)) begin
					crc_reg <= crc16_byte(crc_reg, tx_byte);
				end

				// Load next channel word
				if (tx_is_sync) begin
					ch_word <= 16'h4489; // Sync 0xA1 with missing clock
					prev_data_bit <= 1'b1;
				end else begin
					ch_word <= mfm_encode(tx_byte, prev_data_bit);
					prev_data_bit <= tx_byte[0];
				end
			end
		end
	end

	// Generate 125 ns active-high pulse in the middle of channel bit (cycle 7 of 16)
	wire cur_ch_bit = ch_word[15 - byte_clk_cnt[7:4]];
	assign v_rdata = v_active && !fdc_wg && (byte_clk_cnt[3:0] == 4'd7) && cur_ch_bit;

	// =========================================================================
	// 8. MFM Write Receiver (clk_8)
	// =========================================================================
	reg [6:0]  wr_timer = 7'd0;
	reg [15:0] wr_sh = 16'd0;
	reg [1:0]  wr_sync_cnt = 2'd0;
	reg        wr_aligned = 1'b0;
	reg [3:0]  wr_bit_cnt = 4'd0;
	reg [7:0]  wr_byte_sh = 8'd0;
	reg        wr_byte_strobe = 1'b0;
	reg [7:0]  wr_byte = 8'd0;

	// Edge detector for fdc_wr_data
	reg wr_data_d = 1'b0;
	always @(posedge clk_8) wr_data_d <= fdc_wr_data;
	wire wr_data_pulse = fdc_wr_data && !wr_data_d;

	wire shift_zero = (wr_timer == 7'd23) || (wr_timer == 7'd39) || (wr_timer == 7'd55);

	always @(posedge clk_8) begin
		wr_byte_strobe <= 1'b0;

		if (reset_8 || !fdc_wg) begin
			wr_timer <= 7'd0;
			wr_sh <= 16'd0;
			wr_sync_cnt <= 2'd0;
			wr_aligned <= 1'b0;
			wr_bit_cnt <= 4'd0;
		end else begin
			if (wr_data_pulse) begin
				wr_timer <= 7'd0;
				// Shift 1
				wr_sh <= {wr_sh[14:0], 1'b1};
				if ({wr_sh[14:0], 1'b1} == 16'h4489) begin
					wr_aligned <= 1'b1;
					wr_bit_cnt <= 4'd0;
					if (wr_sync_cnt < 2'd3)
						wr_sync_cnt <= wr_sync_cnt + 2'd1;
				end else if (wr_aligned) begin
					wr_bit_cnt <= wr_bit_cnt + 4'd1;
					if (wr_bit_cnt[0] == 1'b1)
						wr_byte_sh <= {wr_byte_sh[6:0], 1'b1};
					if (wr_bit_cnt == 4'd15) begin
						wr_byte <= {wr_byte_sh[6:0], 1'b1};
						wr_byte_strobe <= 1'b1;
						wr_bit_cnt <= 4'd0;
					end
				end
			end else begin
				if (wr_timer < 7'd127)
					wr_timer <= wr_timer + 7'd1;

				if (shift_zero) begin
					// Shift 0
					wr_sh <= {wr_sh[14:0], 1'b0};
					if ({wr_sh[14:0], 1'b0} == 16'h4489) begin
						wr_aligned <= 1'b1;
						wr_bit_cnt <= 4'd0;
						if (wr_sync_cnt < 2'd3)
							wr_sync_cnt <= wr_sync_cnt + 2'd1;
					end else if (wr_aligned) begin
						wr_bit_cnt <= wr_bit_cnt + 4'd1;
						if (wr_bit_cnt[0] == 1'b1)
							wr_byte_sh <= {wr_byte_sh[6:0], 1'b0};
						if (wr_bit_cnt == 4'd15) begin
							wr_byte <= {wr_byte_sh[6:0], 1'b0};
							wr_byte_strobe <= 1'b1;
							wr_bit_cnt <= 4'd0;
						end
					end
				end
			end
		end
	end

	// Write State Machine
	localparam W_IDLE = 2'd0;
	localparam W_MARK = 2'd1;
	localparam W_DATA = 2'd2;
	localparam W_ID   = 2'd3;

	reg [1:0] w_state = W_IDLE;
	reg [3:0] wr_sec = 4'd0;
	reg [7:0] wr_byte_cnt = 8'd0;
	reg [1:0] wr_id_cnt = 2'd0;
	reg       wr_dirty_pulse = 1'b0;
	wire      wr_active = (w_state == W_DATA);

	always @(posedge clk_8) begin
		ram_b_we <= 1'b0;
		wr_dirty_pulse <= 1'b0;

		if (reset_8 || !fdc_wg) begin
			w_state <= W_IDLE;
			wr_byte_cnt <= 8'd0;
		end else if (wr_byte_strobe) begin
			case (w_state)
				W_IDLE: begin
					// Track sector being passed over
					if (track_byte_cnt >= 13'd80 && track_byte_cnt < 13'd6032)
						wr_sec <= sec_idx;

					if (wr_sync_cnt >= 2'd3) begin
						if (wr_byte == 8'hFB) begin
							// Data Mark: sector data begins
							w_state <= W_DATA;
							wr_byte_cnt <= 8'd0;
						end else if (wr_byte == 8'hFE) begin
							// Address Mark (during FORMAT)
							w_state <= W_ID;
							wr_id_cnt <= 2'd0;
						end
					end
				end

				W_DATA: begin
					// Write byte to BRAM
					ram_b_we <= 1'b1;
					ram_b_din <= wr_byte;
					if (wr_byte_cnt == 8'd255) begin
						wr_dirty_pulse <= 1'b1;
						w_state <= W_IDLE;
					end else begin
						wr_byte_cnt <= wr_byte_cnt + 8'd1;
					end
				end

				W_ID: begin
					// Address header: byte 2 is sector number (1..16)
					if (wr_id_cnt == 2'd2)
						wr_sec <= wr_byte - 8'd1;
					if (wr_id_cnt == 2'd3)
						w_state <= W_IDLE;
					else
						wr_id_cnt <= wr_id_cnt + 2'd1;
				end
			endcase
		end
	end

endmodule
