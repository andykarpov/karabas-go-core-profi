module sram(
	input wire 				clk,
	input wire 				reset,

	input wire 	[20:0] 	port1_a,
	input wire 	[7:0] 	port1_di,
	output wire [7:0] 	port1_do,
	input wire 				port1_ena,
	input wire 				port1_wr,
	input wire 				port1_rd,
	output wire 			port1_do_rdy,

	input wire 	[20:0] 	port2_a,
	input wire 	[7:0] 	port2_di,
	output wire [7:0] 	port2_do,
	input wire 				port2_ena,
	input wire 				port2_wr,
	input wire 				port2_rd,
	output wire 			port2_do_rdy,
	
	output wire [20:0] 	sram_a,
	inout wire 	[15:0] 	sram_d,
	output wire [1:0] 	sram_wr_n,
	output wire [1:0] 	sram_rd_n,
	
	output wire 			busy
);

// FSM states
localparam S_IDLE	= 0;
localparam S_WRITE1_1 = 1;
localparam S_WRITE1_2 = 2;
localparam S_WRITE2_1 = 3;
localparam S_WRITE2_2 = 4;
localparam S_READ1_1 = 5;
localparam S_READ1_2 = 6;
localparam S_READ2_1 = 7;
localparam S_READ2_2 = 8;
localparam S_DONE = 9;

// local regs
reg [20:0] port1_a_r, port2_a_r;
reg [7:0] port1_di_r, port2_di_r;
reg [7:0] port1_do_r, port2_do_r;
reg port1_ena_r, port2_ena_r;
reg [2:0] port1_wr_r, port1_rd_r, port2_wr_r, port2_rd_r;
reg port1_wr_req, port1_rd_req, port2_wr_req, port2_rd_req;
reg port1_do_rdy_r, port2_do_rdy_r;
reg [20:0] sram_a_r;
reg [15:0] sram_di_r;
wire [15:0] sram_do_r;
reg [1:0] sram_wr_n_r, sram_rd_n_r;
reg busy_r;
reg [3:0] state = S_IDLE;

assign sram_a = sram_a_r;
assign sram_d = sram_di_r;
assign sram_do_r = sram_d;
assign sram_wr_n = sram_wr_n_r;
assign sram_rd_n = sram_rd_n_r;

assign port1_do = port1_do_r;
assign port2_do = port2_do_r;
assign port1_do_rdy = port1_do_rdy_r;
assign port2_do_rdy = port2_do_rdy_r;
assign busy = busy_r;

// main FSM
always @(posedge clk, posedge reset)
begin
	if (reset) begin
		port1_ena_r <= 1'b0;
		port2_ena_r <= 1'b0;
		port1_wr_req <= 1'b0;
		port1_rd_req <= 1'b0;
		port2_wr_req <= 1'b0;
		port2_rd_req <= 1'b0;
		port1_wr_r <= 3'b0;
		port1_rd_r <= 3'b0;
		port2_wr_r <= 3'b0;
		port2_rd_r <= 3'b0;
		sram_wr_n_r <= 2'b11;
		sram_rd_n_r <= 2'b11;
		sram_di_r <= 16'bz;
		sram_a_r <= 21'b0;
		port1_a_r <= 21'b0;
		port2_a_r <= 21'b0;
		port1_di_r <= 8'hFF;
		port2_di_r <= 8'hFF;
		port1_do_rdy_r <= 1'b0;
		port2_do_rdy_r <= 1'b0;
		busy_r <= 1'b1;
		state <= S_IDLE;
	end
	else begin
	
		// latch r/w control signals
		port1_wr_r <= {port1_wr_r[1:0], port1_wr};
		port1_rd_r <= {port1_rd_r[1:0], port1_rd};
		port2_wr_r <= {port2_wr_r[1:0], port2_wr};
		port2_rd_r <= {port2_rd_r[1:0], port2_rd};
		port1_ena_r <= port1_ena;
		port2_ena_r <= port2_ena;

		// port 1 r/w req
		if (port1_wr & ~port1_wr_r[0] & ~port1_wr_req & port1_ena) begin
			port1_a_r <= port1_a;
			port1_di_r <= port1_di;
			port1_wr_req <= 1'b1;
		end
		else if (port1_rd & ~port1_rd_r[0] & ~port1_rd_req & port1_ena) begin
			port1_a_r <= port1_a;
			port1_rd_req <= 1'b1;
		end

		// port 2 r/w req
		if (port2_wr & ~port2_wr_r[0] & ~port2_wr_req & port2_ena) begin
			port2_a_r <= port2_a;
			port2_di_r <= port2_di;
			port2_wr_req <= 1'b1;
		end
		else if (port2_rd & ~port2_rd_r[0] & ~port2_rd_req & port2_ena) begin
			port2_a_r <= port2_a;
			port2_rd_req <= 1'b1;
		end

		// state machine
		case (state)
			S_IDLE: begin
				sram_wr_n_r <= 2'b11;
				sram_rd_n_r <= 2'b11;
				sram_di_r <= 16'bz;
				busy_r <= 1'b0;
				
				// port1 wr (direct)
                if (port1_wr & ~port1_wr_r[0] & ~port1_wr_req & port1_ena) begin
                    busy_r <= 1'b1;
					sram_a_r <= port1_a;
                    sram_di_r[7:0] <= port1_di;
				    sram_wr_n_r <= 2'b10;
					state <= S_WRITE1_1;
                end
                // port1 wr (by request)
				else if (port1_wr_req) begin
					busy_r <= 1'b1;
					sram_a_r <= port1_a_r;
                    sram_di_r[7:0] <= port1_di_r;
				    sram_wr_n_r <= 2'b10;
					state <= S_WRITE1_1;
				end
				// port1 rd (direct)
				else if (port1_rd & ~port1_rd_r[0] & ~port1_rd_req & port1_ena) begin
					busy_r <= 1'b1;
					port1_do_rdy_r <= 1'b0;
					sram_a_r <= port1_a;
                    sram_rd_n_r <= 2'b10;
					state <= S_READ1_1;
				end
                // port1 rd (by request)
                else if (port1_rd_req) begin
					busy_r <= 1'b1;
					port1_do_rdy_r <= 1'b0;
					sram_a_r <= port1_a_r;
                    sram_rd_n_r <= 2'b10;
					state <= S_READ1_1;
                end
				// port2 wr (direct)
				else if (port2_wr & ~port2_wr_r[0] & ~port2_wr_req & port2_ena) begin
                    busy_r <= 1'b1;
					sram_a_r <= port2_a;
                    sram_di_r[15:8] <= port2_di;
				    sram_wr_n_r <= 2'b01;
					state <= S_WRITE2_1;
                end
                // port2 wr (by request)
				else if (port2_wr_req) begin
					busy_r <= 1'b1;
					sram_a_r <= port2_a_r;
                    sram_di_r[15:8] <= port2_di_r;
				    sram_wr_n_r <= 2'b01;
					state <= S_WRITE2_1;
				end
				// port2 rd (direct)
				else if (port2_rd & ~port2_rd_r[0] & ~port2_rd_req & port2_ena) begin
					busy_r <= 1'b1;
					port2_do_rdy_r <= 1'b0;
					sram_a_r <= port2_a;
                    sram_rd_n_r <= 2'b01;
					state <= S_READ2_1;
				end
                // port2 rd (by request)
                else if (port2_rd_req) begin
					busy_r <= 1'b1;
					port2_do_rdy_r <= 1'b0;
					sram_a_r <= port2_a_r;
                    sram_rd_n_r <= 2'b01;
					state <= S_READ2_1;
                end
			end
			
			// state read port 1
			S_READ1_1: begin
				port1_rd_req <= 1'b0;
				state <= S_READ1_2;
			end
			
			S_READ1_2: begin
				sram_rd_n_r <= 2'b11;
				port1_do_r <= sram_d[7:0];
				port1_do_rdy_r <= 1'b1;
				state <= S_IDLE;
			end
			
			// state write port 1		
			S_WRITE1_1: begin
				sram_wr_n_r <= 2'b11;
				port1_wr_req <= 1'b0;				
				state <= S_WRITE1_2;
			end
			
			S_WRITE1_2: begin
				sram_di_r[7:0] <= 8'bz;
				state <= S_IDLE;
			end
			
			// state read port 2
			S_READ2_1: begin
				port2_rd_req <= 1'b0;
				state <= S_READ2_2;
			end
			
			S_READ2_2: begin
				sram_rd_n_r <= 2'b11;	
				port2_do_r <= sram_d[15:8];
				port2_do_rdy_r <= 1'b1;
				state <= S_IDLE;
			end
			
			// state write port 2		
			S_WRITE2_1: begin
				sram_wr_n_r <= 2'b11;
				port2_wr_req <= 1'b0;			
				state <= S_WRITE2_2;
			end
			
			S_WRITE2_2: begin
				sram_di_r[15:8] <= 8'bz;
				state <= S_IDLE;
			end
			
			// done
			S_DONE: begin
				sram_wr_n_r <= 2'b11;
				sram_rd_n_r <= 2'b11;
				sram_di_r <= 16'bz;			
				state <= S_IDLE;
			end
			
			default: begin
				sram_wr_n_r <= 2'b11;
				sram_rd_n_r <= 2'b11;
				sram_di_r <= 16'bz;
				state <= S_IDLE;
			end
			
		endcase
	end
end

endmodule
