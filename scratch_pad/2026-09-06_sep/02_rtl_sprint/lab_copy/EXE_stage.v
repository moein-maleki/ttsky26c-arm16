module EXE_stage(
    input               clk,
    input               rst,
    input               do_update_sr_in,
    input               wb_en_in,
    input               mem_r_en_in,
    input               mem_w_en_in,
    input               branch_taken_in,
    input       [3:0]   execute_command_in,
    input       [3:0]   wb_reg_dest_in,
    input       [31:0]  pc_plus_four_in,
    input       [31:0]  branch_immediate_in,
    input       [11:0]  instr_shifter_opperand_in,
    input               instr_is_immediate_in,
    input       [31:0]  val_rn_in,
    input       [31:0]  val_rm_in,
    input       [3:0]   status_bits_in,
    input       [31:0]  frwd_mem_value_in,
    input       [31:0]  frwd_wb_value_in,
    input               frwd_sel_normal_src1_in,
    input               frwd_sel_normal_src2_in,
    input               frwd_sel_mem_src1_in,
    input               frwd_sel_mem_src2_in,
    input               frwd_sel_wb_src1_in,
    input               frwd_sel_wb_src2_in,
    
    output      [3:0]   wb_reg_dest_out,
    output              wb_en_out,
    output              do_update_sr_out,
    output              mem_r_en_out,
    output              mem_w_en_out,
    output      [31:0]  branch_address_out,
    output              branch_taken_out,
    output      [31:0]  alu_result_out,
    output      [31:0]  val_rm_out,
    output      [3:0]   status_bits_out
);

    // val2 generator wires
    wire                instr_is_memory_access;

    // alu wires
    wire        [31:0]  alu_in_1;
    wire        [31:0]  alu_in_2;

    // status register
    assign do_update_sr_out         = do_update_sr_in;

    // control signals passing
    assign wb_reg_dest_out          = wb_reg_dest_in;
    assign wb_en_out                = wb_en_in;
    assign mem_r_en_out             = mem_r_en_in; 
    assign mem_w_en_out             = mem_w_en_in; 
    assign branch_taken_out         = branch_taken_in;

    // forwarding paths
    assign val_rm_out               =
        (frwd_sel_normal_src2_in)      ? (val_rm_in) : 
        (frwd_sel_mem_src2_in)         ? (frwd_mem_value_in) :
        (frwd_sel_wb_src2_in)          ? (frwd_wb_value_in) : 32'b0;
        
    // jump address
    assign branch_address_out       = branch_immediate_in + pc_plus_four_in;

    // val2 generator
    assign instr_is_memory_access   = mem_r_en_in | mem_w_en_in;

    // alu input - forwarding paths
    assign alu_in_1                 =
        (frwd_sel_normal_src1_in)      ? (val_rn_in) : 
        (frwd_sel_mem_src1_in)         ? (frwd_mem_value_in) :
        (frwd_sel_wb_src1_in)          ? (frwd_wb_value_in) : 32'b0;
    
    val2_generator val_unit(
        .val_rm                     (val_rm_out),
        .instr_shifter_opperand     (instr_shifter_opperand_in),
        .instr_is_memory_access     (instr_is_memory_access),
        .instr_is_immediate         (instr_is_immediate_in),
        .val2                       (alu_in_2)
    );

    alu alu_unit(
        .alu_in_1                   (alu_in_1),
        .alu_in_2                   (alu_in_2),
        .execute_command            (execute_command_in),
        .status_bits_in             (status_bits_in),
        .alu_result                 (alu_result_out),
        .status_bits_out            (status_bits_out)
    );

endmodule