// Streaming QSPI master, area probe only. Two changes against the probe version:
//   1. Correct Tiny Tapeout QSPI Pmod pin map and a correct 24-bit byte address.
//   2. Sequential instruction streaming: chip select is held low and the clock kept
//      running while the program counter advances linearly, so a fetch costs only the
//      8 data cycles instead of a full command/address/dummy transaction.
// A branch, or any data access, breaks the stream and pays the full transaction again.
module qspi_master_streaming(
    input               clk,
    input               rst,

    input               instr_req_in,
    input       [23:0]  instr_addr_in,
    output reg  [31:0]  instr_data_out,
    output reg          instr_ready_out,

    input               data_re_in,
    input               data_we_in,
    input       [23:0]  data_addr_in,
    input       [15:0]  data_wdata_in,
    output reg  [15:0]  data_rdata_out,
    output reg          data_ready_out,

    output reg          qspi_sck_out,
    output reg          qspi_cs_flash_n_out,
    output reg          qspi_cs_rama_n_out,
    output      [3:0]   qspi_dq_out,
    output reg  [3:0]   qspi_dq_oe_out,
    input       [3:0]   qspi_dq_in
);
    localparam IDLE=3'd0, CMD=3'd1, ADDR=3'd2, DUMMY=3'd3, DATA=3'd4, HOLD=3'd5;

    reg [2:0]  state;
    reg [5:0]  bitcnt;
    reg [31:0] shifter;
    reg [31:0] rxreg;
    reg        is_instr, is_write;
    reg [3:0]  dq_o;

    // stream tracking: the byte address the device will return next while CS stays low
    reg [23:0] stream_next_addr;
    reg        stream_open;

    wire stream_hit = stream_open & instr_req_in & (instr_addr_in == stream_next_addr);

    assign qspi_dq_out = dq_o;

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE; bitcnt <= 0; qspi_sck_out <= 0;
            qspi_cs_flash_n_out <= 1; qspi_cs_rama_n_out <= 1; qspi_dq_oe_out <= 4'b0000;
            instr_ready_out <= 0; data_ready_out <= 0; instr_data_out <= 0; data_rdata_out <= 0;
            shifter <= 0; rxreg <= 0; is_instr <= 0; is_write <= 0; dq_o <= 0;
            stream_next_addr <= 0; stream_open <= 0;
        end else begin
            instr_ready_out <= 0; data_ready_out <= 0;
            case (state)
                IDLE: begin
                    qspi_sck_out <= 0;
                    if (stream_hit) begin
                        // stay in the open flash read, just clock 8 more nibbles
                        bitcnt <= 6'd8; is_instr <= 1; is_write <= 0;
                        qspi_dq_oe_out <= 4'b0000; state <= DATA;
                    end else if (instr_req_in) begin
                        is_instr <= 1; is_write <= 0;
                        shifter <= {8'hEB, instr_addr_in};        // quad I/O read, true byte address
                        qspi_cs_flash_n_out <= 0; qspi_cs_rama_n_out <= 1;
                        qspi_dq_oe_out <= 4'b1111;
                        bitcnt <= 6'd8; state <= CMD; stream_open <= 0;
                    end else if (data_re_in | data_we_in) begin
                        is_instr <= 0; is_write <= data_we_in;
                        shifter <= {8'hEB, data_addr_in};
                        qspi_cs_flash_n_out <= 1; qspi_cs_rama_n_out <= 0;
                        qspi_dq_oe_out <= 4'b1111;
                        bitcnt <= 6'd8; state <= CMD; stream_open <= 0;
                    end
                end
                CMD, ADDR: begin
                    qspi_sck_out <= ~qspi_sck_out;
                    if (qspi_sck_out) begin
                        dq_o    <= shifter[31:28];
                        shifter <= {shifter[27:0], 4'b0};
                        bitcnt  <= bitcnt - 1;
                        if (bitcnt == 1) begin bitcnt <= 6'd6; state <= DUMMY; end
                    end
                end
                DUMMY: begin
                    qspi_sck_out <= ~qspi_sck_out;
                    qspi_dq_oe_out <= is_write ? 4'b1111 : 4'b0000;
                    if (qspi_sck_out) begin
                        bitcnt <= bitcnt - 1;
                        if (bitcnt == 1) begin bitcnt <= is_instr ? 6'd8 : 6'd4; state <= DATA; end
                    end
                end
                DATA: begin
                    qspi_sck_out <= ~qspi_sck_out;
                    if (qspi_sck_out) begin
                        rxreg  <= {rxreg[27:0], qspi_dq_in};
                        bitcnt <= bitcnt - 1;
                        if (bitcnt == 1) state <= HOLD;
                    end
                end
                HOLD: begin
                    qspi_sck_out <= 0;
                    if (is_instr) begin
                        instr_data_out   <= rxreg;
                        instr_ready_out  <= 1;
                        // keep flash selected so the next linear fetch can stream
                        stream_next_addr <= instr_addr_in + 24'd4;
                        stream_open      <= 1;
                        qspi_cs_flash_n_out <= 0;
                    end else begin
                        data_rdata_out <= rxreg[15:0];
                        data_ready_out <= 1;
                        qspi_cs_rama_n_out <= 1;
                        stream_open    <= 0;
                    end
                    qspi_dq_oe_out <= 4'b0000;
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
