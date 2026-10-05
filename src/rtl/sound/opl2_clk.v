module opl2_clk (
    input  wire clk, // 28/24 MHz
    input  wire reset, 
	 input  wire ds80,
    output reg clk_en // 3.579545 MHz
);

    reg [15:0] accumulator;
	 // (3.579 / 28.0) * 2^16= 8377
	 localparam [15:0] FTW = 16'd8377;
	 // (3.579 / 24.0) * 2^16= 9773
	 localparam [15:0] FTW_DS80 = 16'd9773;	 
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            accumulator <= 16'h0;
				clk_en <= 0;
        end else begin
            {clk_en, accumulator} <= accumulator + (ds80 ? FTW_DS80 : FTW);
        end
    end

endmodule
