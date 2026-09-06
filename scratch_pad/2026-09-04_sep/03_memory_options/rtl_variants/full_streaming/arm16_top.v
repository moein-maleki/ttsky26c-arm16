// arm16 top with the streaming QSPI master and the official Tiny Tapeout QSPI Pmod pin map:
//   uio[0]=CS0 flash  uio[1]=SD0  uio[2]=SD1  uio[3]=SCK  uio[4]=SD2  uio[5]=SD3  uio[6]=CS1 RAM-A  uio[7]=CS2 RAM-B
module arm16_top(
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);
    wire rst = ~rst_n;
    wire [15:0] pc, mem_addr, mem_wdata, mem_rdata;
    wire [31:0] instr_data;
    wire instr_req, instr_ready, mem_we, mem_re, mem_ready;
    wire [3:0] dq_o, dq_oe;
    wire sck, cs_f_n, cs_ra_n;

    arm_processor cpu(
        .clk(clk), .rst(rst), .use_forwarding(ui_in[0]),
        .pc_out(pc), .instr_req_out(instr_req),
        .instr_data_in(instr_data), .instr_ready_in(instr_ready),
        .mem_addr_out(mem_addr), .mem_wdata_out(mem_wdata),
        .mem_we_out(mem_we), .mem_re_out(mem_re),
        .mem_rdata_in(mem_rdata), .mem_ready_in(mem_ready)
    );

    qspi_master_streaming qspi(
        .clk(clk), .rst(rst),
        .instr_req_in(instr_req), .instr_addr_in({8'h00, pc}),
        .instr_data_out(instr_data), .instr_ready_out(instr_ready),
        .data_re_in(mem_re), .data_we_in(mem_we),
        .data_addr_in({7'h00, mem_addr, 1'b0}), .data_wdata_in(mem_wdata),
        .data_rdata_out(mem_rdata), .data_ready_out(mem_ready),
        .qspi_sck_out(sck), .qspi_cs_flash_n_out(cs_f_n), .qspi_cs_rama_n_out(cs_ra_n),
        .qspi_dq_out(dq_o), .qspi_dq_oe_out(dq_oe),
        .qspi_dq_in({uio_in[5], uio_in[4], uio_in[2], uio_in[1]})
    );

    assign uo_out  = ui_in[1] ? pc[15:8] : pc[7:0];
    //                 uio7    uio6     uio5     uio4     uio3  uio2     uio1     uio0
    assign uio_out = {1'b1,   cs_ra_n, dq_o[3], dq_o[2], sck,  dq_o[1], dq_o[0], cs_f_n};
    assign uio_oe  = {1'b1,   1'b1,    dq_oe[3],dq_oe[2],1'b1, dq_oe[1],dq_oe[0],1'b1};
endmodule
