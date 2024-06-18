module zc_spi
(
	input wire        clk_sys,
	input wire 			ena,

	input wire        tx,        // Byte ready to be transmitted
	input wire        rx,        // request to read one byte
	input wire  [7:0] din,
	output wire [7:0] dout,

	output wire       spi_clk,
	input wire        spi_di,
	output wire       spi_do,
	output reg	 		spi_wait
);

assign    spi_clk = counter[0];
assign    spi_do  = io_byte[7]; // data is shifted up during transfer
assign    dout    = data;

reg [4:0] counter = 5'b10000;  // tx/rx counter is idle
reg [7:0] io_byte, data;
reg tx_stb, rx_stb;
reg prev_tx, prev_rx;
reg spi_clk_stb, prev_spi_clk;

// tx/rx/spi_clk strobes
always @(posedge clk_sys) begin
	tx_stb <= 1'b0;
	rx_stb <= 1'b0;
	spi_clk_stb <= 1'b0;
	if (~prev_tx && tx) tx_stb <= 1'b1;
	if (~prev_rx && rx) rx_stb <= 1'b1;
	if (~prev_spi_clk && spi_clk) spi_clk_stb <= 1'b1;
	prev_tx <= tx;
	prev_rx <= rx;	
	prev_spi_clk <= spi_clk;
end

// shift register
always @(negedge clk_sys) begin
	 if(counter[4]) begin
		spi_wait <= 1'b0;
		  if(rx_stb | tx_stb) begin
				counter <= 0;
				data <= io_byte;
				io_byte <= tx_stb ? din : 8'hff;
		  end
	 end 
	 else begin
		if (counter >= 4) spi_wait <= 1'b1; // wait cycle with a small delay
		if (ena) begin
			if(spi_clk) io_byte <= { io_byte[6:0], spi_di };
			counter <= counter + 2'd1;
		end 
	 end
end

endmodule
