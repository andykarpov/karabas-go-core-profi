module Z80pa (
    input wire RESET_n,
    input wire CLK,
    input wire WAIT_n,
    input wire INT_n,
    input wire NMI_n,
    input wire BUSRQ_n,
    output wire M1_n,
    output wire MREQ_n,
    output wire IORQ_n,
    output wire RD_n,
    output wire WR_n,
    output wire RFSH_n,
    output wire HALT_n,
    output wire BUSACK_n,
    output wire [15:0] A,
    input wire [7:0] DI,
    output wire [7:0] DO
);

wire mreq, iorq, rd, wr, rfsh, m1, halt, busack;

Z80 Z80(
    .clk(CLK),
    .data_in(DI),
    .data_out(DO),
    .adr(A),
    .mreq(mreq),
    .iorq(iorq),
    .rd(rd),
    .wr(wr),
    .data_z(),
    .adr_z(),
    .controls_z(),
    .rfsh(rfsh),
    .p_m1(m1),
    .halt(halt),
    .p_wait(~WAIT_n),
    .p_int(~INT_n),
    .nmi(~NMI_n),
    .reset(~RESET_n),
    .busrq(~BUSRQ_n),
    .busack(busack)
);

assign MREQ_n = ~mreq;
assign IORQ_n = ~iorq;
assign RD_n = ~rd;
assign WR_n = ~wr;
assign RFSH_n = ~rfsh;
assign M1_n = ~m1;
assign HALT_n = ~halt;
assign BUSACK_n = ~busack;

endmodule

