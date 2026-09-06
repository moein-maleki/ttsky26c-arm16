// QSPI engine (docs/spec.md 3.3, sprint plan task 4). One SPI-mode EBh stream on the flash with the chip
// select held (8 SCK per 32-bit word), one-shot 16-bit reads on the flash or the PSRAM (EBh) and 16-bit
// writes on the PSRAM (38h). SCK = core/2: `sck_reg` toggles in the core domain and a falling-edge flop
// copies it to the pad, so data (launched on core rising edges) leads SCK by half a core cycle. The
// receive sampler captures the four lanes `rx_delay_in` core clocks (1 to 3) after the tick that
// launched the falling edge which clocks the nibble out of the chip (plan D9). A word of the stream
// is only requested when the controller reports room for it (plan D4). The PSRAM chip select is
// forced high after CS_LOW_MAX core clocks (6 us, seen on the following edge: 6.04 us), SCK and the
// lane enables drop with it, and the fault is sticky.
`default_nettype none
module qspi_master #(
    parameter TICK_RATIO = 2,
    parameter CS_LOW_MAX = 150,
    parameter GAP_CYCLES = 2
) (
    input  wire        clk,
    input  wire        rst,
    input  wire [1:0]  rx_delay_in,
    input  wire        stream_start_in,
    input  wire        stream_stop_in,
    input  wire        data_start_in,
    input  wire        data_flash_in,
    input  wire        data_write_in,
    input  wire [15:0] addr_in,
    input  wire [15:0] wdata_in,
    input  wire        word_take_in,
    input  wire        word_room_in,
    input  wire [3:0]  sd_in,
    output wire        busy_out,
    output wire        word_valid_out,
    output wire        data_done_out,
    output wire [31:0] rdata_out,
    output wire        fault_out,
    output wire        sck_out,
    output wire        cs_flash_n_out,
    output wire        cs_ram_a_n_out,
    output wire        cs_ram_b_n_out,
    output wire [3:0]  sd_out,
    output wire [3:0]  sd_oe_out
);
    localparam [2:0] E_IDLE = 3'd0;
    localparam [2:0] E_PRE  = 3'd1;
    localparam [2:0] E_DATA = 3'd2;
    localparam [2:0] E_STOP = 3'd3;
    localparam [2:0] E_GAP  = 3'd4;

    localparam [1:0] KIND_STREAM     = 2'd0;
    localparam [1:0] KIND_FLASH_DATA = 2'd1;
    localparam [1:0] KIND_RAM_READ   = 2'd2;
    localparam [1:0] KIND_RAM_WRITE  = 2'd3;

    localparam [7:0] CMD_READ  = 8'hEB;
    localparam [7:0] CMD_WRITE = 8'h38;
    localparam [4:0] LAST_PREAMBLE_PERIOD = 5'd19;   // the falling edge of period 19 launches data nibble 0
    localparam [4:0] LAST_WRITE_PERIOD    = 5'd17;   // cmd 8 + address 6 + four data nibbles

    wire        start_any;
    wire        kind_is_write;
    wire        kind_is_flash;
    wire        kind_is_stream;
    wire        kind_is_data;
    wire [1:0]  kind_next;
    wire        capture_now;
    wire        pipe_empty;
    wire        rising_allowed;
    wire        tcem_expired;
    wire [4:0]  period_next;
    wire [2:0]  rx_lane;

    reg  [2:0]  present_state;
    reg  [2:0]  next_state;
    reg  [1:0]  kind;
    reg         sck_reg;
    reg         sck_pad;
    reg         cs_flash_n_reg;
    reg         cs_ram_n_reg;
    reg  [3:0]  sd_reg;
    reg  [3:0]  sd_oe_reg;
    reg         write_cmd;
    reg  [15:0] addr_reg;
    reg  [15:0] wdata_reg;
    reg  [4:0]  period;
    reg  [3:0]  req_cnt;
    reg  [3:1]  cap_pipe;
    reg  [2:0]  cap_count;
    reg  [31:0] rx_word;
    reg         word_valid_reg;
    reg         data_done_reg;
    reg         fault_reg;
    reg  [7:0]  cs_low_cnt;
    reg  [3:0]  gap_cnt;
    reg         stop_pending;
    reg  [3:0]  tx_nibble;
    reg  [3:0]  tx_oe;
    reg  [7:0]  cmd_byte;

    assign start_any      = stream_start_in | data_start_in;
    assign kind_next      = stream_start_in ? KIND_STREAM :
                            (data_flash_in ? KIND_FLASH_DATA : (data_write_in ? KIND_RAM_WRITE : KIND_RAM_READ));
    assign kind_is_write  = (kind == KIND_RAM_WRITE);
    assign kind_is_flash  = (kind == KIND_STREAM) | (kind == KIND_FLASH_DATA);
    assign kind_is_stream = (kind == KIND_STREAM);
    assign kind_is_data   = (kind != KIND_STREAM);
    assign capture_now    = (rx_delay_in == 2'd2) ? cap_pipe[2] : ((rx_delay_in == 2'd3) ? cap_pipe[3] : cap_pipe[1]);
    assign pipe_empty     = (cap_pipe == 3'b000);
    assign rising_allowed = ~((present_state == E_DATA) & kind_is_stream & (req_cnt == 4'd8) & ~word_room_in);
    assign tcem_expired   = (cs_low_cnt >= CS_LOW_MAX[7:0]);
    assign period_next    = period + 5'd1;
    assign rx_lane        = cap_count ^ 3'b001;

    assign busy_out       = (present_state != E_IDLE);
    assign word_valid_out = word_valid_reg;
    assign data_done_out  = data_done_reg;
    assign rdata_out      = rx_word;
    assign fault_out      = fault_reg;
    assign sck_out        = sck_pad;
    assign cs_flash_n_out = cs_flash_n_reg;
    assign cs_ram_a_n_out = cs_ram_n_reg;
    assign cs_ram_b_n_out = 1'b1;
    assign sd_out         = sd_reg;
    assign sd_oe_out      = sd_oe_reg;

    // ---------------------------------------------------------------- state register
    always @(posedge clk) begin
        if (rst) begin
            present_state <= E_IDLE;
        end else begin
            present_state <= next_state;
        end
    end

    // ---------------------------------------------------------------- SCK pad: half a core cycle behind sck_reg
    always @(negedge clk) begin
        sck_pad <= sck_reg;
    end

    // ---------------------------------------------------------------- transaction setup and the clocked protocol
    always @(posedge clk) begin
        if (rst) begin
            kind           <= KIND_STREAM;
            sck_reg        <= 1'b0;
            cs_flash_n_reg <= 1'b1;
            cs_ram_n_reg   <= 1'b1;
            sd_reg         <= 4'b0000;
            sd_oe_reg      <= 4'b0000;
            write_cmd      <= 1'b0;
            addr_reg       <= 16'h0000;
            wdata_reg      <= 16'h0000;
            period         <= 5'd0;
            req_cnt        <= 4'd0;
            stop_pending   <= 1'b0;
            gap_cnt        <= 4'd0;
        end else begin
            case (present_state)
                E_IDLE: begin
                    sck_reg      <= 1'b0;
                    stop_pending <= 1'b0;
                    gap_cnt      <= 4'd0;
                    req_cnt      <= 4'd0;
                    if (start_any) begin
                        kind      <= kind_next;
                        write_cmd <= data_start_in & data_write_in;
                        addr_reg  <= addr_in;
                        wdata_reg <= wdata_in;
                        period    <= 5'd0;
                        sd_reg    <= {3'b000, (data_start_in & data_write_in) ? CMD_WRITE[7] : CMD_READ[7]};
                        sd_oe_reg <= 4'b0001;
                        if (stream_start_in | data_flash_in) begin
                            cs_flash_n_reg <= 1'b0;
                        end else begin
                            cs_ram_n_reg <= 1'b0;
                        end
                    end
                end
                E_PRE, E_DATA: begin
                    if (stream_stop_in & kind_is_stream) begin
                        stop_pending <= 1'b1;
                    end
                    if (sck_reg) begin
                        // falling launch: present the next nibble, advance the period
                        sck_reg <= 1'b0;
                        if (present_state == E_PRE) begin
                            period    <= period_next;
                            sd_oe_reg <= tx_oe;
                            if (tx_oe != 4'b0000) begin
                                sd_reg <= tx_nibble;
                            end
                            if (period == LAST_PREAMBLE_PERIOD) begin
                                req_cnt <= 4'd1;
                            end
                        end else begin
                            req_cnt <= req_cnt + 4'd1;
                        end
                    end else if (rising_allowed & ~stop_pending & ~(stream_stop_in & kind_is_stream)) begin
                        sck_reg <= 1'b1;
                        if ((present_state == E_DATA) & (req_cnt == 4'd8)) begin
                            req_cnt <= 4'd0;
                        end
                    end
                end
                E_STOP: begin
                    sck_reg   <= 1'b0;
                    sd_oe_reg <= 4'b0000;
                    if (pipe_empty | stop_pending) begin
                        cs_flash_n_reg <= 1'b1;
                        cs_ram_n_reg   <= 1'b1;
                    end
                end
                E_GAP: begin
                    gap_cnt   <= gap_cnt + 4'd1;
                    sck_reg   <= 1'b0;
                    sd_oe_reg <= 4'b0000;
                end
                default: begin
                    sck_reg <= 1'b0;
                end
            endcase
            if (tcem_expired & ~cs_ram_n_reg) begin
                cs_ram_n_reg <= 1'b1;
                sck_reg      <= 1'b0;
                sd_oe_reg    <= 4'b0000;
                stop_pending <= 1'b1;
            end
        end
    end

    // ---------------------------------------------------------------- receive path: capture requests, the delay line, the word
    always @(posedge clk) begin
        if (rst) begin
            cap_pipe       <= 3'b000;
            cap_count      <= 3'd0;
            rx_word        <= 32'h0000_0000;
            word_valid_reg <= 1'b0;
        end else begin
            cap_pipe <= {cap_pipe[2:1], 1'b0};
            if ((present_state == E_PRE) & sck_reg & (period == LAST_PREAMBLE_PERIOD) & ~kind_is_write) begin
                cap_pipe[1] <= 1'b1;
            end
            if ((present_state == E_DATA) & sck_reg) begin
                cap_pipe[1] <= 1'b1;
            end
            if (stop_pending | (present_state == E_IDLE)) begin
                cap_pipe <= 3'b000;
            end
            if (word_take_in) begin
                word_valid_reg <= 1'b0;
            end
            if (capture_now & ~stop_pending) begin
                rx_word[rx_lane * 4 +: 4] <= sd_in;
                cap_count <= cap_count + 3'd1;
                if (kind_is_stream & (cap_count == 3'd7)) begin
                    word_valid_reg <= 1'b1;
                end
            end
            if (present_state == E_IDLE) begin
                cap_count      <= 3'd0;
                word_valid_reg <= 1'b0;
            end
            if (stop_pending) begin
                word_valid_reg <= 1'b0;
                cap_count      <= 3'd0;
            end
        end
    end

    // ---------------------------------------------------------------- data-transaction completion, tCEM, fault
    always @(posedge clk) begin
        if (rst) begin
            data_done_reg <= 1'b0;
            fault_reg     <= 1'b0;
            cs_low_cnt    <= 8'd0;
        end else begin
            data_done_reg <= 1'b0;
            if ((present_state == E_STOP) & kind_is_data & (pipe_empty | stop_pending) & ~data_done_reg) begin
                data_done_reg <= 1'b1;
            end
            if (tcem_expired & ~cs_ram_n_reg) begin
                fault_reg     <= 1'b1;
                data_done_reg <= 1'b1;
            end
            if (cs_ram_n_reg) begin
                cs_low_cnt <= 8'd0;
            end else begin
                cs_low_cnt <= cs_low_cnt + 8'd1;
            end
        end
    end

    // ---------------------------------------------------------------- next state
    always @* begin
        next_state = present_state;
        case (present_state)
            E_IDLE: begin
                if (start_any) begin
                    next_state = E_PRE;
                end
            end
            E_PRE: begin
                if (stop_pending | (stream_stop_in & kind_is_stream)) begin
                    next_state = E_STOP;
                end else if (sck_reg & kind_is_write & (period == LAST_WRITE_PERIOD)) begin
                    next_state = E_STOP;
                end else if (sck_reg & ~kind_is_write & (period == LAST_PREAMBLE_PERIOD)) begin
                    next_state = E_DATA;
                end
            end
            E_DATA: begin
                if (stop_pending | (stream_stop_in & kind_is_stream)) begin
                    next_state = E_STOP;
                end else if (sck_reg & kind_is_data & (req_cnt == 4'd3)) begin
                    next_state = E_STOP;
                end
            end
            E_STOP: begin
                if (pipe_empty | stop_pending) begin
                    next_state = E_GAP;
                end
            end
            E_GAP: begin
                if (gap_cnt >= GAP_CYCLES[3:0]) begin
                    next_state = E_IDLE;
                end
            end
            default: begin
                next_state = E_IDLE;
            end
        endcase
        if (tcem_expired & ~cs_ram_n_reg) begin
            next_state = E_GAP;
        end
    end

    // ---------------------------------------------------------------- transmit nibble for the next period
    always @* begin
        tx_nibble = 4'b0000;
        tx_oe     = 4'b0000;
        cmd_byte  = write_cmd ? CMD_WRITE : CMD_READ;
        if (period_next < 5'd8) begin
            tx_nibble = {3'b000, cmd_byte[3'd7 - period_next[2:0]]};
            tx_oe     = 4'b0001;
        end else if (period_next < 5'd14) begin
            case (period_next)
                5'd8:    tx_nibble = 4'b0000;
                5'd9:    tx_nibble = 4'b0000;
                5'd10:   tx_nibble = addr_reg[15:12];
                5'd11:   tx_nibble = addr_reg[11:8];
                5'd12:   tx_nibble = addr_reg[7:4];
                default: tx_nibble = addr_reg[3:0];
            endcase
            tx_oe = 4'b1111;
        end else if (kind_is_write & (period_next < 5'd18)) begin
            case (period_next)
                5'd14:   tx_nibble = wdata_reg[7:4];
                5'd15:   tx_nibble = wdata_reg[3:0];
                5'd16:   tx_nibble = wdata_reg[15:12];
                default: tx_nibble = wdata_reg[11:8];
            endcase
            tx_oe = 4'b1111;
        end else if (kind_is_flash & (period_next < 5'd16)) begin
            tx_nibble = 4'b1111;       // mode byte FFh: continuous read stays off
            tx_oe     = 4'b1111;
        end
    end
endmodule
`default_nettype wire
