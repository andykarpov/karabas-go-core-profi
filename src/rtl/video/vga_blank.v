module vga_blank
(
	input wire        clk,
	input wire 			ds80,
	input wire [1:0]  screen_mode,
	input wire 			pix_start,
	output wire 		blank
);

parameter SINGLE_CLOCK = 0;

// pentagon 768x608 -> 720x576 (offset x: 24, offset y: 16)
parameter [11:0] SPEC_FRAME_WIDTH = 896;  // 448
parameter [11:0] SPEC_FRAME_HEIGHT = 640; // 320
parameter [11:0] SPEC_IMAGE_WIDTH = 720; //720; // 768;  // 384 
parameter [11:0] SPEC_IMAGE_HEIGHT = 576; //576; // 608; // 304
parameter [11:0] SPEC_OFFSET_X = 24;
parameter [11:0] SPEC_OFFSET_Y = 16;
parameter [15:0] SPEC_START_DELAY = SPEC_FRAME_WIDTH * SPEC_OFFSET_Y + SPEC_OFFSET_X - 124;

// classic 768x560 -> 720x560 (offset x: 24, offset y: 0)
parameter [11:0] SPEC2_FRAME_WIDTH = 896;  // 448
parameter [11:0] SPEC2_FRAME_HEIGHT = 624; // 312
parameter [11:0] SPEC2_IMAGE_WIDTH = 720;  // 384
parameter [11:0] SPEC2_IMAGE_HEIGHT = 560; // 288
parameter [11:0] SPEC2_OFFSET_X = 24;
parameter [11:0] SPEC2_OFFSET_Y = 0;
parameter [15:0] SPEC2_START_DELAY = SPEC2_FRAME_WIDTH * SPEC2_OFFSET_Y + SPEC2_OFFSET_X - 124;

// profi 608x480 -> 640x480 (offset x: 32, offset y: 0)
parameter [11:0] PROFI_FRAME_WIDTH = 768;
parameter [11:0] PROFI_FRAME_HEIGHT = 624; // 312
parameter [11:0] PROFI_IMAGE_WIDTH = 640; // 640
parameter [11:0] PROFI_IMAGE_HEIGHT = 480; // 240
parameter [11:0] PROFI_OFFSET_X = 24;
parameter [11:0] PROFI_OFFSET_Y = 1;
parameter [15:0] PROFI_START_DELAY = PROFI_FRAME_WIDTH * PROFI_OFFSET_Y - PROFI_OFFSET_X - 92;

// profi 28mhz 608x480 -> 640x480 (offset x: 32, y : 0)
parameter [11:0] PROFI2_FRAME_WIDTH = 768;
parameter [11:0] PROFI2_FRAME_HEIGHT = 640; // 320
parameter [11:0] PROFI2_IMAGE_WIDTH = 640; //640;
parameter [11:0] PROFI2_IMAGE_HEIGHT = 480; // 240
parameter [11:0] PROFI2_OFFSET_X = 24;
parameter [11:0] PROFI2_OFFSET_Y = 16;
parameter [15:0] PROFI2_START_DELAY = PROFI2_FRAME_WIDTH * PROFI2_OFFSET_Y - PROFI2_OFFSET_X - 92;


reg [11:0] hcnt, vcnt = 12'd0;
reg [15:0] delay = 16'd0;
reg pix_start_r = 1'b0;
reg prev_pix_start = 1'b0;
wire delayed_pix_start = (ds80) ? ((SINGLE_CLOCK == 1) ? (delay == PROFI2_START_DELAY) : (delay == PROFI_START_DELAY)) : ((screen_mode == 2'b01) ? (delay == SPEC2_START_DELAY) : (delay == SPEC_START_DELAY));
wire end_frame_h = (ds80) ? ((SINGLE_CLOCK == 1) ? (hcnt >= PROFI2_FRAME_WIDTH-1) : (hcnt >= PROFI_FRAME_WIDTH-1)) : (hcnt >= SPEC_FRAME_WIDTH-1);
wire end_frame_v = (ds80) ? ((SINGLE_CLOCK == 1) ? (vcnt >= PROFI2_FRAME_HEIGHT-1) : (vcnt >= PROFI_FRAME_HEIGHT-1)) : ((screen_mode == 2'b01) ? (vcnt >= SPEC2_FRAME_HEIGHT-1) : (vcnt >= SPEC_FRAME_HEIGHT-1));
wire end_image_h = (ds80) ? ((SINGLE_CLOCK == 1) ? (hcnt >= PROFI2_IMAGE_WIDTH) : (hcnt >= PROFI_IMAGE_WIDTH)) : (hcnt >= SPEC_IMAGE_WIDTH);
wire end_image_v = (ds80) ? ((SINGLE_CLOCK == 1) ? (vcnt >= PROFI2_IMAGE_HEIGHT) : (vcnt >= PROFI_IMAGE_HEIGHT)) : ((screen_mode == 2'b01) ? (vcnt >= SPEC2_IMAGE_HEIGHT) : (vcnt >= SPEC_IMAGE_HEIGHT));

always @(posedge clk) begin
	pix_start_r <= pix_start;
end

always @(posedge clk) begin
	if (!prev_pix_start && pix_start_r)
		delay <= 0;
	else if (delay < 65534)
		delay <= delay + 1;
		
	prev_pix_start <= pix_start_r;
end

always @(posedge clk) begin	
	if (delayed_pix_start) begin
//	if (!prev_pix_start && pix_start) begin
		hcnt <= 0;
		vcnt <= 0;
	end
	else
	begin
		if (end_frame_h) begin
			hcnt <= 0;
			if (end_frame_v) 
				vcnt <= 0;
			else 
				vcnt <= vcnt + 1;
		end
		else
			hcnt <= hcnt + 1;
	end
end

assign blank = ( end_image_h || end_image_v );

endmodule
