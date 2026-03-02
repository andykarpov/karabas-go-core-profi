`timescale 1ns / 1ps
`default_nettype none

module zhdmi_top(

	input wire clk,
	input wire ds80,

	input wire reset,
	
	input wire [23:0] vga_rgb,
	input wire vga_hs,
	input wire vga_vs,
	input wire vga_de,
	
	input wire audio_en,
	input wire [15:0] audio_l,
	input wire [15:0] audio_r,
	
	output wire [3:0] tmds_p,
	output wire [3:0] tmds_n	
);

parameter SAMPLERATE = 32000;

// clocks
wire clk_hdmi, clk_hdmi_n;
wire p_clk_int, p_clk_div2;
wire [7:0] hdmi_freq;
wire lockedx5;
wire pll_reset;
hdmi_pll hdmi_pll (
	.clk(clk),
	.reset(reset),
	.ds80(ds80),
	.clk_hdmi(clk_hdmi),
	.clk_hdmi_n(clk_hdmi_n),
	.clk_pix(p_clk_int),
	.clk_pix2(p_clk_div2),
	.freq(hdmi_freq),
	.locked(lockedx5),
	.o_reset(pll_reset)
);

wire audio_clk;

audio_samplerate #(.SAMPLERATE(SAMPLERATE)) audio_samplerate(
	.clk(p_clk_int),
	.reset(reset),
	.clkrate(hdmi_freq),
	.audio_stb(audio_clk)
);

reg signed [23:0] hdmi_audio_l, hdmi_audio_r;
always @(posedge p_clk_int) begin
	if (audio_clk) begin
		hdmi_audio_l <= $signed(audio_l) * 256;
		hdmi_audio_r <= $signed(audio_r) * 256;
	end
end

// hdmi tx
hdmi_tx #(.SAMPLE_FREQ(SAMPLERATE)) hdmi_tx(
	.clk(p_clk_int),
	.sclk(clk_hdmi),
	.sclk_n(clk_hdmi_n),
	.reset(reset || ~lockedx5),
	.rgb(vga_rgb),
	.vsync(vga_vs),
	.hsync(vga_hs),
	.de(vga_de),
	
	.audio_en(audio_en),
	.audio_l(hdmi_audio_l),
	.audio_r(hdmi_audio_r),
	.audio_clk(audio_clk),
	
	.tx_clk_n(tmds_n[3]),
	.tx_clk_p(tmds_p[3]),
	.tx_d_n(tmds_n[2:0]),
	.tx_d_p(tmds_p[2:0]) // 0:blue, 1:green, 2:red
);

endmodule
