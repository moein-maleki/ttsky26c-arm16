// arm16 datapath (docs/spec.md): the five-stage pipeline, the register file, the flags, the fetch
// address and the delivered word, the address decode and the peripheral registers, the meter, the
// display selection, and every pin-facing unit (QSPI engine, VGA renderer). The controller sequences
// it through the command inputs and reads the status outputs.
`default_nettype none
module arm16_datapath (
    input  wire        clk,
    input  wire        rst,
    input  wire [7:0]  pins_in,
    input  wire [3:0]  qspi_sd_in,
    input  wire        stream_start_in,
    input  wire        stream_stop_in,
    input  wire        data_start_in,
    input  wire        data_flash_in,
    input  wire        data_write_in,
    input  wire        word_take_in,
    input  wire        word_room_in,
    input  wire        addr_sel_in,
    input  wire        fetch_addr_load_in,
    input  wire        fetch_addr_inc_in,
    input  wire        fetch_word_load_in,
    input  wire        fetch_src_rom_in,
    input  wire        if_id_load_in,
    input  wire        if_id_bubble_in,
    input  wire        id_ex_bubble_in,
    input  wire        mem_busy_in,
    output wire        rom_mode_out,
    output wire        busy_out,
    output wire        word_valid_out,
    output wire        data_done_out,
    output wire        redirect_out,
    output wire        mem_access_out,
    output wire        mem_write_out,
    output wire        addr_is_flash_out,
    output wire        hazard_out,
    output wire [7:0]  video_pins_out,
    output wire [3:0]  qspi_sd_out,
    output wire [3:0]  qspi_sd_oe_out,
    output wire        qspi_sck_out,
    output wire        cs_flash_n_out,
    output wire        cs_ram_a_n_out,
    output wire        cs_ram_b_n_out
);
    localparam [6:0]  PERIPH_VGA_VAL   = 7'h00;
    localparam [6:0]  PERIPH_SW        = 7'h01;
    localparam [6:0]  PERIPH_UART_DATA = 7'h02;
    localparam [6:0]  PERIPH_UART_STAT = 7'h03;
    localparam [6:0]  PERIPH_UART_DIV  = 7'h04;
    localparam [6:0]  PERIPH_METER     = 7'h06;
    localparam [6:0]  PERIPH_VGA_FG    = 7'h08;
    localparam [6:0]  PERIPH_VGA_BG    = 7'h09;

    // ---------------------------------------------------------------- decode stage nets
    wire        id_valid_dec;
    wire [3:0]  id_cond;
    wire        id_is_load;
    wire        id_is_store;
    wire        id_is_branch;
    wire        id_link;
    wire        id_wb_en;
    wire        id_set_flags;
    wire [3:0]  id_command;
    wire        id_immediate;
    wire        id_memory;
    wire [3:0]  id_dest;
    wire        id_dest_is_pc;
    wire [3:0]  id_src1;
    wire [3:0]  id_src2;
    wire        id_has_src1;
    wire        id_has_src2;
    wire [11:0] id_operand2;
    wire [23:0] id_branch_imm;
    wire        id_cond_met;
    wire        id_live;
    wire        id_exec;
    wire [15:0] rf_read_first;
    wire [15:0] rf_read_second;
    wire [15:0] id_pc_plus_8;
    wire [15:0] id_val_rn;
    wire [15:0] id_val_rm;
    wire        hazard;
    // ---------------------------------------------------------------- execute stage nets
    wire [1:0]  fwd_sel1;
    wire [1:0]  fwd_sel2;
    wire [15:0] shifter_result;
    wire [15:0] alu_result;
    wire        alu_carry;
    wire        alu_overflow;
    wire        alu_arith;
    wire        alu_negative;
    wire        alu_zero;
    wire [3:0]  flags_next;
    wire        flags_write;
    wire [3:0]  cond_flags;
    wire [15:0] ex_pc_plus_4;
    wire [15:0] ex_pc_plus_8;
    wire [15:0] ex_branch_target;
    wire [15:0] ex_result;
    // ---------------------------------------------------------------- memory stage nets
    wire        mem_addr_is_periph;
    wire [6:0]  mem_periph_index;
    wire        mem_periph_write;
    wire [15:0] mem_load_data;
    wire        retired_pulse;
    // ---------------------------------------------------------------- write-back nets
    wire [15:0] wb_value;
    // ---------------------------------------------------------------- engine and display nets
    wire [15:0] engine_addr;
    wire        engine_busy;
    wire        engine_word_valid;
    wire        engine_data_done;
    wire [31:0] engine_rdata;
    wire        engine_fault;
    wire [31:0] rom_word;
    wire [31:0] presented_word;
    wire        presented_valid;
    wire        uart_tx;
    wire [15:0] display_value;
    wire [5:0]  display_fg;
    wire [5:0]  display_bg;
    wire [7:0]  vga_pins;
    wire        vga_vsync;
    wire        disp_sel;
    wire        uart_en;
    wire        user_sel;

    // ---------------------------------------------------------------- registers
    reg         fwd_en_q;
    reg  [1:0]  rx_delay_q;
    reg         rom_mode_q;
    reg  [15:0] fetch_addr;
    reg  [31:0] fetch_word;
    reg         d_valid;
    reg         ex_valid;
    reg  [15:0] ex_pc;
    reg         ex_wb_en;
    reg         ex_mem_read;
    reg         ex_mem_write;
    reg         ex_branch;
    reg         ex_link;
    reg         ex_set_flags;
    reg  [3:0]  ex_dest;
    reg         ex_dest_is_pc;
    reg  [3:0]  ex_command;
    reg         ex_immediate;
    reg         ex_memory;
    reg  [11:0] ex_operand2;
    reg  [13:0] ex_branch_imm;
    reg  [15:0] ex_val_rn;
    reg  [15:0] ex_val_rm;
    reg  [3:0]  ex_src1;
    reg  [3:0]  ex_src2;
    reg         ex_has_src1;
    reg         ex_has_src2;
    reg  [3:0]  ex_flags;
    reg  [15:0] ex_operand_a;
    reg  [15:0] ex_operand_rm;
    reg         mem_valid;
    reg         mem_wb_en;
    reg         mem_mem_read;
    reg         mem_mem_write;
    reg  [3:0]  mem_dest;
    reg  [15:0] mem_alu_result;
    reg  [15:0] mem_store_data;
    reg  [15:0] mem_periph_read;
    reg         wb_valid;
    reg         wb_wb_en;
    reg         wb_mem_read;
    reg  [3:0]  wb_dest;
    reg  [15:0] wb_alu_result;
    reg  [15:0] wb_load_data;
    reg  [3:0]  nzcv;
    reg  [15:0] vga_val;
    reg  [5:0]  vga_fg;
    reg  [5:0]  vga_bg;
    reg  [19:0] retired_count;
    reg  [15:0] meter_value;
    reg         vsync_q;

    // ---------------------------------------------------------------- continuous assignments
    assign disp_sel       = pins_in[1];
    assign uart_en        = pins_in[2];
    assign user_sel       = pins_in[7];
    assign rom_mode_out   = rom_mode_q;
    assign presented_word  = fetch_src_rom_in ? rom_word : fetch_word;
    assign presented_valid = fetch_src_rom_in | d_valid;

    assign id_live        = presented_valid & id_valid_dec;
    assign id_exec        = id_live & id_cond_met;
    assign id_pc_plus_8   = fetch_addr + 16'd8;
    assign id_val_rn      = (id_src1 == 4'd15) ? id_pc_plus_8 : rf_read_first;
    assign id_val_rm      = (id_src2 == 4'd15) ? id_pc_plus_8 : rf_read_second;
    assign hazard_out     = hazard;

    assign ex_pc_plus_4     = ex_pc + 16'd4;
    assign ex_pc_plus_8     = ex_pc + 16'd8;
    assign ex_branch_target = ex_branch ? (ex_pc_plus_8 + {ex_branch_imm[13:0], 2'b00}) : {alu_result[15:2], 2'b00};
    assign ex_result        = ex_link ? ex_pc_plus_4 : alu_result;
    assign redirect_out     = ex_valid & (ex_branch | ex_dest_is_pc);
    assign flags_next       = {alu_negative, alu_zero, alu_arith ? alu_carry : ex_flags[1], alu_arith ? alu_overflow : ex_flags[0]};
    assign flags_write      = ex_valid & ex_set_flags;
    assign cond_flags       = flags_write ? flags_next : nzcv;

    assign mem_addr_is_periph = (mem_alu_result[15:8] == 8'hFF);
    assign mem_periph_index   = mem_alu_result[7:1];
    assign addr_is_flash_out  = ~mem_alu_result[15];
    assign mem_write_out      = mem_mem_write;
    assign mem_access_out     = mem_valid & (mem_mem_read | mem_mem_write) & ~mem_addr_is_periph & ~(mem_mem_write & ~mem_alu_result[15]);
    assign mem_periph_write   = mem_valid & mem_mem_write & mem_addr_is_periph & ~mem_busy_in;
    assign mem_load_data      = mem_addr_is_periph ? mem_periph_read : engine_rdata[15:0];
    assign retired_pulse      = wb_valid & ~mem_busy_in;

    assign wb_value = wb_mem_read ? wb_load_data : wb_alu_result;

    assign engine_addr    = addr_sel_in ? {1'b0, mem_alu_result[14:1], 1'b0} : fetch_addr;
    assign busy_out       = engine_busy;
    assign word_valid_out = engine_word_valid;
    assign data_done_out  = engine_data_done;
    assign uart_tx        = 1'b1;
    assign display_value  = disp_sel ? (user_sel ? meter_value : fetch_addr) : vga_val;
    assign display_fg     = disp_sel ? 6'b111111 : vga_fg;
    assign display_bg     = disp_sel ? (engine_busy ? 6'b000001 : 6'b000000) : vga_bg;
    assign video_pins_out = uart_en ? {1'b1, 2'b00, uart_tx, 1'b1, 3'b000} : vga_pins;

    // ---------------------------------------------------------------- strap latches (spec 10)
    always @(posedge clk) begin
        if (rst) begin
            fwd_en_q   <= pins_in[0];
            rx_delay_q <= pins_in[5:4];
            rom_mode_q <= pins_in[6];
        end
    end

    // ---------------------------------------------------------------- fetch address and delivered word
    always @(posedge clk) begin
        if (rst) begin
            fetch_addr <= 16'h0000;
        end else if (fetch_addr_load_in) begin
            fetch_addr <= ex_branch_target;
        end else if (fetch_addr_inc_in) begin
            fetch_addr <= fetch_addr + 16'd4;
        end
    end

    // The delivered word D is the decode-stage instruction register of the streamed path: the word at
    // fetch_addr sits in D until decode accepts it (if_id_load_in), a refill in the same cycle keeps
    // d_valid set, and a redirect drops it (if_id_bubble_in). In ROM mode decode reads the ROM word at
    // fetch_addr directly. A word with condition 1111 is never valid (the drain policy's bubble).
    always @(posedge clk) begin
        if (fetch_word_load_in) begin
            fetch_word <= engine_rdata;
        end
    end

    always @(posedge clk) begin
        if (rst | if_id_bubble_in) begin
            d_valid <= 1'b0;
        end else if (fetch_word_load_in) begin
            d_valid <= (engine_rdata[31:28] != 4'b1111);
        end else if (if_id_load_in) begin
            d_valid <= 1'b0;
        end
    end

    // ---------------------------------------------------------------- ID/EX register
    always @(posedge clk) begin
        if (rst | (id_ex_bubble_in & ~mem_busy_in)) begin
            ex_valid      <= 1'b0;
            ex_pc         <= 16'h0000;
            ex_wb_en      <= 1'b0;
            ex_mem_read   <= 1'b0;
            ex_mem_write  <= 1'b0;
            ex_branch     <= 1'b0;
            ex_link       <= 1'b0;
            ex_set_flags  <= 1'b0;
            ex_dest       <= 4'd0;
            ex_dest_is_pc <= 1'b0;
            ex_command    <= 4'd0;
            ex_immediate  <= 1'b0;
            ex_memory     <= 1'b0;
            ex_operand2   <= 12'd0;
            ex_branch_imm <= 14'd0;
            ex_val_rn     <= 16'h0000;
            ex_val_rm     <= 16'h0000;
            ex_src1       <= 4'd0;
            ex_src2       <= 4'd0;
            ex_has_src1   <= 1'b0;
            ex_has_src2   <= 1'b0;
            ex_flags      <= 4'b0000;
        end else if (~mem_busy_in) begin
            ex_valid      <= id_live;
            ex_pc         <= fetch_addr;
            ex_wb_en      <= id_exec & id_wb_en;
            ex_mem_read   <= id_exec & id_is_load;
            ex_mem_write  <= id_exec & id_is_store;
            ex_branch     <= id_exec & id_is_branch;
            ex_link       <= id_exec & id_link;
            ex_set_flags  <= id_exec & id_set_flags;
            ex_dest       <= id_dest;
            ex_dest_is_pc <= id_exec & id_dest_is_pc;
            ex_command    <= id_exec ? id_command : 4'd0;
            ex_immediate  <= id_immediate;
            ex_memory     <= id_memory;
            ex_operand2   <= id_operand2;
            ex_branch_imm <= id_branch_imm[13:0];
            ex_val_rn     <= id_val_rn;
            ex_val_rm     <= id_val_rm;
            ex_src1       <= id_src1;
            ex_src2       <= id_src2;
            ex_has_src1   <= id_exec & id_has_src1;
            ex_has_src2   <= id_exec & id_has_src2;
            ex_flags      <= cond_flags;
        end
    end

    // ---------------------------------------------------------------- EX/MEM register
    always @(posedge clk) begin
        if (rst) begin
            mem_valid      <= 1'b0;
            mem_wb_en      <= 1'b0;
            mem_mem_read   <= 1'b0;
            mem_mem_write  <= 1'b0;
            mem_dest       <= 4'd0;
            mem_alu_result <= 16'h0000;
            mem_store_data <= 16'h0000;
        end else if (~mem_busy_in) begin
            mem_valid      <= ex_valid;
            mem_wb_en      <= ex_wb_en;
            mem_mem_read   <= ex_mem_read;
            mem_mem_write  <= ex_mem_write;
            mem_dest       <= ex_dest;
            mem_alu_result <= ex_result;
            mem_store_data <= ex_operand_rm;
        end
    end

    // ---------------------------------------------------------------- MEM/WB register
    always @(posedge clk) begin
        if (rst) begin
            wb_valid      <= 1'b0;
            wb_wb_en      <= 1'b0;
            wb_mem_read   <= 1'b0;
            wb_dest       <= 4'd0;
            wb_alu_result <= 16'h0000;
            wb_load_data  <= 16'h0000;
        end else if (~mem_busy_in) begin
            wb_valid      <= mem_valid;
            wb_wb_en      <= mem_wb_en;
            wb_mem_read   <= mem_mem_read;
            wb_dest       <= mem_dest;
            wb_alu_result <= mem_alu_result;
            wb_load_data  <= mem_load_data;
        end
    end

    // ---------------------------------------------------------------- flags (plan D10): written on the rising edge and
    // bypassed into decode through cond_flags, so the condition check sees the execute stage's flags in the same
    // cycle without a half-period path; the execute stage reads the snapshot taken into ID/EX
    always @(posedge clk) begin
        if (rst) begin
            nzcv <= 4'b0000;
        end else if (flags_write & ~mem_busy_in) begin
            nzcv <= flags_next;
        end
    end

    // ---------------------------------------------------------------- peripheral registers (spec 3.4); the UART is
    // dropped by the area rule of section 11 (plan D13): its registers read 0, UART_EN still blanks the video
    always @(posedge clk) begin
        if (rst) begin
            vga_val  <= 16'h0000;
            vga_fg   <= 6'b111111;
            vga_bg   <= 6'b000000;
        end else if (mem_periph_write) begin
            if (mem_periph_index == PERIPH_VGA_VAL) begin
                vga_val <= mem_store_data;
            end
            if (mem_periph_index == PERIPH_VGA_FG) begin
                vga_fg <= mem_store_data[5:0];
            end
            if (mem_periph_index == PERIPH_VGA_BG) begin
                vga_bg <= mem_store_data[5:0];
            end
        end
    end

    // ---------------------------------------------------------------- retired-per-frame meter: METER = retired / 16, so a
    // ROM-mode frame (about 360,000 retired) fits 16 bits and the FWD_EN ratio stays visible
    always @(posedge clk) begin
        if (rst) begin
            retired_count <= 20'h00000;
            meter_value   <= 16'h0000;
            vsync_q       <= 1'b1;
        end else begin
            vsync_q <= vga_vsync;
            if (vsync_q & ~vga_vsync) begin
                meter_value   <= retired_count[19:4];
                retired_count <= {19'd0, retired_pulse};
            end else if (retired_pulse) begin
                retired_count <= retired_count + 20'd1;
            end
        end
    end

    // ---------------------------------------------------------------- execute operand selection
    always @* begin
        ex_operand_a = ex_val_rn;
        case (fwd_sel1)
            2'b01:   ex_operand_a = mem_alu_result;
            2'b10:   ex_operand_a = wb_value;
            default: ex_operand_a = ex_val_rn;
        endcase
    end

    always @* begin
        ex_operand_rm = ex_val_rm;
        case (fwd_sel2)
            2'b01:   ex_operand_rm = mem_alu_result;
            2'b10:   ex_operand_rm = wb_value;
            default: ex_operand_rm = ex_val_rm;
        endcase
    end

    // ---------------------------------------------------------------- peripheral read mux
    always @* begin
        mem_periph_read = 16'h0000;
        case (mem_periph_index)
            PERIPH_VGA_VAL:   mem_periph_read = vga_val;
            PERIPH_SW:        mem_periph_read = {8'h00, pins_in};
            PERIPH_UART_DATA: mem_periph_read = 16'h0000;
            PERIPH_UART_STAT: mem_periph_read = 16'h0000;
            PERIPH_UART_DIV:  mem_periph_read = 16'h0000;
            PERIPH_METER:     mem_periph_read = meter_value;
            PERIPH_VGA_FG:    mem_periph_read = {10'd0, vga_fg};
            PERIPH_VGA_BG:    mem_periph_read = {10'd0, vga_bg};
            default:          mem_periph_read = 16'h0000;
        endcase
    end

    // ---------------------------------------------------------------- units, in data-flow order
    demo_rom demo_rom_unit (
        .address_in (fetch_addr[15:2]),
        .word_out   (rom_word)
    );

    instruction_decoder instruction_decoder_unit (
        .instr_in       (presented_word),
        .valid_out      (id_valid_dec),
        .cond_out       (id_cond),
        .is_load_out    (id_is_load),
        .is_store_out   (id_is_store),
        .is_branch_out  (id_is_branch),
        .link_out       (id_link),
        .wb_en_out      (id_wb_en),
        .set_flags_out  (id_set_flags),
        .command_out    (id_command),
        .immediate_out  (id_immediate),
        .memory_out     (id_memory),
        .dest_out       (id_dest),
        .dest_is_pc_out (id_dest_is_pc),
        .src1_out       (id_src1),
        .src2_out       (id_src2),
        .has_src1_out   (id_has_src1),
        .has_src2_out   (id_has_src2),
        .operand2_out   (id_operand2),
        .branch_imm_out (id_branch_imm)
    );

    condition_checker condition_checker_unit (
        .cond_in  (id_cond),
        .flags_in (cond_flags),
        .met_out  (id_cond_met)
    );

    register_file register_file_unit (
        .clk                  (clk),
        .read_first_addr_in   (id_src1),
        .read_second_addr_in  (id_src2),
        .write_en_in          (wb_wb_en),
        .write_addr_in        (wb_dest),
        .write_data_in        (wb_value),
        .read_first_data_out  (rf_read_first),
        .read_second_data_out (rf_read_second)
    );

    hazard_detector hazard_detector_unit (
        .fwd_en_in      (fwd_en_q),
        .id_valid_in    (id_live),
        .id_src1_in     (id_src1),
        .id_src2_in     (id_src2),
        .id_has_src1_in (id_has_src1),
        .id_has_src2_in (id_has_src2),
        .ex_wb_en_in    (ex_wb_en),
        .ex_dest_in     (ex_dest),
        .ex_mem_read_in (ex_mem_read),
        .mem_wb_en_in   (mem_wb_en),
        .mem_dest_in    (mem_dest),
        .hazard_out     (hazard)
    );

    forwarding_selector forwarding_selector_unit (
        .fwd_en_in      (fwd_en_q),
        .ex_src1_in     (ex_src1),
        .ex_src2_in     (ex_src2),
        .ex_has_src1_in (ex_has_src1),
        .ex_has_src2_in (ex_has_src2),
        .mem_wb_en_in   (mem_wb_en),
        .mem_dest_in    (mem_dest),
        .wb_wb_en_in    (wb_wb_en),
        .wb_dest_in     (wb_dest),
        .sel1_out       (fwd_sel1),
        .sel2_out       (fwd_sel2)
    );

    barrel_shifter barrel_shifter_unit (
        .value_in     (ex_operand_rm),
        .operand2_in  (ex_operand2),
        .immediate_in (ex_immediate),
        .memory_in    (ex_memory),
        .result_out   (shifter_result)
    );

    alu alu_unit (
        .operand_a_in (ex_operand_a),
        .operand_b_in (shifter_result),
        .command_in   (ex_command),
        .carry_in     (ex_flags[1]),
        .result_out   (alu_result),
        .carry_out    (alu_carry),
        .overflow_out (alu_overflow),
        .arith_out    (alu_arith),
        .negative_out (alu_negative),
        .zero_out     (alu_zero)
    );

    qspi_master qspi_master_unit (
        .clk             (clk),
        .rst             (rst),
        .rx_delay_in     (rx_delay_q),
        .stream_start_in (stream_start_in),
        .stream_stop_in  (stream_stop_in),
        .data_start_in   (data_start_in),
        .data_flash_in   (data_flash_in),
        .data_write_in   (data_write_in),
        .addr_in         (engine_addr),
        .wdata_in        (mem_store_data),
        .word_take_in    (word_take_in),
        .word_room_in    (word_room_in),
        .sd_in           (qspi_sd_in),
        .busy_out        (engine_busy),
        .word_valid_out  (engine_word_valid),
        .data_done_out   (engine_data_done),
        .rdata_out       (engine_rdata),
        .fault_out       (engine_fault),
        .sck_out         (qspi_sck_out),
        .cs_flash_n_out  (cs_flash_n_out),
        .cs_ram_a_n_out  (cs_ram_a_n_out),
        .cs_ram_b_n_out  (cs_ram_b_n_out),
        .sd_out          (qspi_sd_out),
        .sd_oe_out       (qspi_sd_oe_out)
    );

    vga_renderer vga_renderer_unit (
        .clk       (clk),
        .rst       (rst),
        .enable_in (~uart_en),
        .value_in  (display_value),
        .fg_in     (display_fg),
        .bg_in     (display_bg),
        .pins_out  (vga_pins),
        .vsync_out (vga_vsync)
    );
endmodule
`default_nettype wire
