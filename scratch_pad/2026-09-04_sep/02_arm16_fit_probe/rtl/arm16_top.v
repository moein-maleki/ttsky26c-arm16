// TinyTapeout-style top: 16-bit pipelined ARM subset with forwarding, hazard detection and
// condition codes, no cache, instructions and data fetched serially from an external QSPI Pmod.
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
    wire qclk, cs_f_n, cs_r_n;

    arm_processor cpu(
        .clk(clk), .rst(rst), .use_forwarding(ui_in[0]),
        .pc_out(pc), .instr_req_out(instr_req),
        .instr_data_in(instr_data), .instr_ready_in(instr_ready),
        .mem_addr_out(mem_addr), .mem_wdata_out(mem_wdata),
        .mem_we_out(mem_we), .mem_re_out(mem_re),
        .mem_rdata_in(mem_rdata), .mem_ready_in(mem_ready)
    );

    qspi_master qspi(
        .clk(clk), .rst(rst),
        .instr_req_in(instr_req), .instr_addr_in(pc),
        .instr_data_out(instr_data), .instr_ready_out(instr_ready),
        .data_re_in(mem_re), .data_we_in(mem_we),
        .data_addr_in(mem_addr), .data_wdata_in(mem_wdata),
        .data_rdata_out(mem_rdata), .data_ready_out(mem_ready),
        .qspi_clk_out(qclk), .qspi_cs_flash_n_out(cs_f_n), .qspi_cs_ram_n_out(cs_r_n),
        .qspi_dq_out(dq_o), .qspi_dq_oe_out(dq_oe), .qspi_dq_in(uio_in[3:0])
    );

    // observable output: low or high byte of the program counter, selected by a switch
    assign uo_out  = ui_in[1] ? pc[15:8] : pc[7:0];
    assign uio_out = {1'b0, cs_r_n, cs_f_n, qclk, dq_o};
    assign uio_oe  = {1'b0, 3'b111, dq_oe};
endmodule
