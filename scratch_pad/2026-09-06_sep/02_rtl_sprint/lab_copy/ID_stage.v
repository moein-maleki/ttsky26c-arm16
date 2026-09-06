module ID_stage(
    input               clk,
    input               rst,
    input               hazard_in,
    input       [3:0]   wb_dest_in,
    input       [31:0]  wb_value_in,
    input               wb_wb_en_in,
    input       [31:0]  instruction_in,
    input       [3:0]   status_bits_in,
    input       [31:0]  pc_plus_four_in,

    // control signals
    output              wb_en_out,
    output              mem_r_en_out,
    output              mem_w_en_out,
    output              branch_taken_out,
    output      [3:0]   execute_command_out,
    output              do_update_sr_out,
    output      [3:0]   wb_reg_dest_out,

    // pc passing
    output      [31:0]  pc_plus_four_out,

    // immediates 
    output      [31:0]  branch_immediate_out,
    output              instr_is_immediate_out,
    output      [11:0]  instr_shifter_opperand_out,

    // register file
    output      [31:0]  val_rn_out,
    output      [31:0]  val_rm_out,

    // hazard_in unit
    output              instr_has_src1_out,
    output              instr_has_src2_out,
    output              hazard_two_src_out,
    output      [3:0]   hazard_src1_out,
    output      [3:0]   hazard_src2_out,

    // forwarding signals
    output      [3:0]   exe_src1_out,
    output      [3:0]   exe_src2_out
);

    // instruction bits
    wire        [3:0]   instr_condition;
    wire        [1:0]   instr_mode;
    wire        [3:0]   instr_opcode;
    wire                instr_do_update_sr;
    wire                do_update_sr_decoded;
    wire        [3:0]   instr_rn;
    wire        [3:0]   instr_rd;
    wire        [3:0]   instr_rm;
    wire        [23:0]  instr_signed_immed_24;

    // condition check unit
    wire                condition_is_met;

    // register file
    wire        [3:0]   regfile_1st_read_input;
    wire        [31:0]  regfile_1st_read_output;
    wire        [3:0]   regfile_2nd_read_input;
    wire        [31:0]  regfile_2nd_read_output;

    // control unit
    wire                wb_en_cu;
    wire                mem_r_en_cu;
    wire                mem_w_en_cu;
    wire                branch_taken_cu;
    wire        [3:0]   execute_command_cu;
    wire                terminate_ctrl_signals;

    // output signals
    assign hazard_two_src_out       = instr_has_src2_out;
    assign hazard_src1_out          = regfile_1st_read_input;
    assign hazard_src2_out          = regfile_2nd_read_input;
    assign val_rn_out               = regfile_1st_read_output;
    assign val_rm_out               = regfile_2nd_read_output;

    // instruction decode
    assign instr_condition          = instruction_in[31:28];
    assign instr_mode               = instruction_in[27:26];
    assign instr_is_immediate_out   = instruction_in[25];
    assign instr_opcode             = instruction_in[24:21];
    assign instr_do_update_sr       = instruction_in[20];
    assign do_update_sr_decoded     = instr_do_update_sr & (instr_mode == 2'b00);
    assign instr_rn                 = instruction_in[19:16];
    assign instr_rd                 = instruction_in[15:12];
    assign instr_shifter_opperand_out = instruction_in[11:0];
    assign instr_rm                 = instruction_in[3:0];
    assign instr_signed_immed_24    = instruction_in[23:0];

    // forwarding unit
    assign exe_src1_out             = regfile_1st_read_input;
    assign exe_src2_out             = regfile_2nd_read_input;

    // pc passing
    assign pc_plus_four_out         = pc_plus_four_in;

    // register file
    assign regfile_1st_read_input   = instr_rn;
    assign regfile_2nd_read_input   = (mem_w_en_out) ? (instr_rd) : (instr_rm);

    // immediates
    assign branch_immediate_out     = $signed(instr_signed_immed_24);

    // control unit
    assign terminate_ctrl_signals   = (~condition_is_met | hazard_in);
    assign wb_en_out                = (terminate_ctrl_signals) ? (1'b0) : (wb_en_cu);
    assign mem_r_en_out             = (terminate_ctrl_signals) ? (1'b0) : (mem_r_en_cu);
    assign mem_w_en_out             = (terminate_ctrl_signals) ? (1'b0) : (mem_w_en_cu);
    assign branch_taken_out         = (terminate_ctrl_signals) ? (1'b0) : (branch_taken_cu);
    assign execute_command_out      = (terminate_ctrl_signals) ? (4'b0) : (execute_command_cu);
    assign do_update_sr_out         = (terminate_ctrl_signals) ? (1'b0) : (do_update_sr_decoded);
    assign wb_reg_dest_out          = instr_rd;

    condition_check cond_unit (
        .instr_condition        (instr_condition),
        .status_register        (status_bits_in),
        .condition_is_met       (condition_is_met)
    );

    control_unit ctrl_unit(
        .instr_do_update_sr     (instr_do_update_sr),
        .instr_opcode           (instr_opcode),
        .instr_mode             (instr_mode),
        .instr_has_src1         (instr_has_src1_out),
        .instr_has_src2         (instr_has_src2_out),
        .instr_is_immediate     (instr_is_immediate_out),
        .wb_en                  (wb_en_cu),
        .mem_r_en               (mem_r_en_cu),
        .mem_w_en               (mem_w_en_cu),
        .branch_taken           (branch_taken_cu),
        .execute_command        (execute_command_cu)
    );

    register_file regfile_unit (
        .clk                    (clk),
        .rst                    (rst),
        .read_src_1_reg         (regfile_1st_read_input),
        .read_src_2_reg         (regfile_2nd_read_input),
        .write_src_reg          (wb_dest_in),
        .wb_en                  (wb_wb_en_in),
        .wb_value               (wb_value_in),
        .read_src_1_data        (regfile_1st_read_output),
        .read_src_2_data        (regfile_2nd_read_output)
    );

endmodule