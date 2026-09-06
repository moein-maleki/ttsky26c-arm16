// QSPI master for an external flash and PSRAM Pmod. Serves instruction fetch (two 16-bit words per
// 32-bit ARM instruction) and data load/store, sharing one four-bit bus. Command, 24-bit address,
// dummy cycles, then four bits per clock.
module qspi_master(
    input               clk,
    input               rst,

    // instruction side
    input               instr_req_in,
    input       [15:0]  instr_addr_in,
    output reg  [31:0]  instr_data_out,
    output reg          instr_ready_out,

    // data side
    input               data_re_in,
    input               data_we_in,
    input       [15:0]  data_addr_in,
    input       [15:0]  data_wdata_in,
    output reg  [15:0]  data_rdata_out,
    output reg          data_ready_out,

    // pins
    output reg          qspi_clk_out,
    output reg          qspi_cs_flash_n_out,
    output reg          qspi_cs_ram_n_out,
    output      [3:0]   qspi_dq_out,
    output reg  [3:0]   qspi_dq_oe_out,
    input       [3:0]   qspi_dq_in
);
    localparam IDLE=3'd0, CMD=3'd1, ADDR=3'd2, DUMMY=3'd3, DATA=3'd4, DONE=3'd5;
    reg [2:0]  state;
    reg [5:0]  bitcnt;
    reg [31:0] shifter;
    reg [31:0] rxreg;
    reg        is_instr, is_write;
    reg [3:0]  dq_o;

    assign qspi_dq_out = dq_o;

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE; bitcnt <= 0; qspi_clk_out <= 0;
            qspi_cs_flash_n_out <= 1; qspi_cs_ram_n_out <= 1; qspi_dq_oe_out <= 4'b0000;
            instr_ready_out <= 0; data_ready_out <= 0; instr_data_out <= 0; data_rdata_out <= 0;
            shifter <= 0; rxreg <= 0; is_instr <= 0; is_write <= 0; dq_o <= 0;
        end else begin
            instr_ready_out <= 0; data_ready_out <= 0;
            case (state)
                IDLE: begin
                    qspi_clk_out <= 0;
                    if (instr_req_in) begin
                        is_instr <= 1; is_write <= 0;
                        shifter <= {8'h6B, instr_addr_in, 8'h00};
                        qspi_cs_flash_n_out <= 0; qspi_dq_oe_out <= 4'b1111;
                        bitcnt <= 6'd8; state <= CMD;
                    end else if (data_re_in | data_we_in) begin
                        is_instr <= 0; is_write <= data_we_in;
                        shifter <= {8'hEB, data_addr_in, 8'h00};
                        qspi_cs_ram_n_out <= 0; qspi_dq_oe_out <= 4'b1111;
                        bitcnt <= 6'd8; state <= CMD;
                    end
                end
                CMD, ADDR: begin
                    qspi_clk_out <= ~qspi_clk_out;
                    if (qspi_clk_out) begin
                        dq_o    <= shifter[31:28];
                        shifter <= {shifter[27:0], 4'b0};
                        bitcnt  <= bitcnt - 1;
                        if (bitcnt == 1) begin bitcnt <= 6'd6; state <= DUMMY; end
                    end
                end
                DUMMY: begin
                    qspi_clk_out <= ~qspi_clk_out;
                    qspi_dq_oe_out <= is_write ? 4'b1111 : 4'b0000;
                    if (qspi_clk_out) begin
                        bitcnt <= bitcnt - 1;
                        if (bitcnt == 1) begin bitcnt <= is_instr ? 6'd8 : 6'd4; state <= DATA; end
                    end
                end
                DATA: begin
                    qspi_clk_out <= ~qspi_clk_out;
                    if (qspi_clk_out) begin
                        rxreg  <= {rxreg[27:0], qspi_dq_in};
                        bitcnt <= bitcnt - 1;
                        if (bitcnt == 1) state <= DONE;
                    end
                end
                DONE: begin
                    qspi_clk_out <= 0; qspi_cs_flash_n_out <= 1; qspi_cs_ram_n_out <= 1;
                    qspi_dq_oe_out <= 4'b0000;
                    if (is_instr) begin instr_data_out <= rxreg; instr_ready_out <= 1; end
                    else          begin data_rdata_out <= rxreg[15:0]; data_ready_out <= 1; end
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
