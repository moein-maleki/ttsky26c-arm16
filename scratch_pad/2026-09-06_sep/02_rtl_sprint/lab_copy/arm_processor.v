module arm_processor(
    input               clk,
    input               rst,
    input               use_forwarding
);

    // hazard unit wires
    wire                hazard_out_hazard;

    // forwarding wires
    wire                frwd_in_instr_has_src1;
    wire                frwd_in_instr_has_src2;
    wire                frwd_out_sel_normal_src1;
    wire                frwd_out_sel_normal_src2;
    wire                frwd_out_sel_mem_src1;
    wire                frwd_out_sel_mem_src2;
    wire                frwd_out_sel_wb_src1;
    wire                frwd_out_sel_wb_src2;
    
    // status bits
    wire        [3:0]   srreg_out_status_bits;

    // if stage wires
    wire        [31:0]  if_out_pc_plus_four;
    wire        [31:0]  if_out_instruction;

    // id stage wires
    wire        [31:0]  id_in_instruction;
    wire        [31:0]  id_in_pc_plus_four;
    wire                id_out_wb_en;
    wire                id_out_mem_r_en;
    wire                id_out_mem_w_en;
    wire                id_out_branch_taken;
    wire        [3:0]   id_out_execute_command;
    wire                id_out_do_update_sr;
    wire        [3:0]   id_out_wb_reg_dest;
    wire        [31:0]  id_out_pc_plus_four;
    wire        [31:0]  id_out_branch_immediate;
    wire        [11:0]  id_out_instr_shifter_opperand;
    wire                id_out_instr_is_immediate;
    wire                id_out_hazard_two_src;
    wire        [3:0]   id_out_hazard_src1;
    wire        [3:0]   id_out_hazard_src2;
    wire        [31:0]  id_out_val_rn;
    wire        [31:0]  id_out_val_rm;
    wire                id_out_instr_has_src1;
    wire                id_out_instr_has_src2;
    wire        [3:0]   id_out_exe_src1;
    wire        [3:0]   id_out_exe_src2;
    
    // exe stage wires
    wire                exe_in_do_update_sr;
    wire                exe_in_wb_en;
    wire                exe_in_mem_r_en;
    wire                exe_in_mem_w_en;
    wire                exe_in_branch_taken;
    wire        [3:0]   exe_in_execute_command;
    wire        [3:0]   exe_in_wb_reg_dest;
    wire        [31:0]  exe_in_pc_plus_four;
    wire        [31:0]  exe_in_branch_immediate;
    wire        [31:0]  exe_in_val_rn;
    wire        [31:0]  exe_in_val_rm;
    wire        [11:0]  exe_in_instr_shifter_opperand;
    wire                exe_in_instr_is_immediate;
    wire        [3:0]   exe_in_status_bits;
    wire        [3:0]   exe_in_exe_src1;
    wire        [3:0]   exe_in_exe_src2;

    wire        [3:0]   exe_out_wb_reg_dest;
    wire                exe_out_wb_en;
    wire                exe_out_mem_r_en;
    wire                exe_out_mem_w_en;
    wire        [3:0]   exe_out_status_bits;
    wire        [31:0]  exe_out_branch_address;
    wire                exe_out_do_update_sr;
    wire                exe_out_branch_taken;
    wire        [31:0]  exe_out_alu_result;
    wire        [31:0]  exe_out_val_rm;

    // mem stage wires
    wire                mem_in_wb_en;
    wire                mem_in_mem_r_en;
    wire                mem_in_mem_w_en;
    wire        [31:0]  mem_in_alu_result;
    wire        [3:0]   mem_in_wb_reg_dest;  
    wire        [31:0]  mem_in_val_rm;
    wire                mem_out_wb_en;
    wire                mem_out_mem_r_en;
    wire        [31:0]  mem_out_alu_result;
    wire        [31:0]  mem_out_data_memory_result;
    wire        [3:0]   mem_out_wb_reg_dest;
    wire        [31:0]  mem_out_frwd_value;
    
    // wb stage wires
    wire                wb_in_wb_en;
    wire                wb_in_mem_r_en;
    wire        [31:0]  wb_in_alu_result;
    wire        [31:0]  wb_in_data_memory_result;
    wire        [3:0]   wb_in_wb_reg_dest;
    wire        [31:0]  wb_out_wb_value;
    wire                wb_out_wb_en;
    wire        [3:0]   wb_out_wb_reg_dest;

    hazard_detection hazard_unit(
        .id_src1_in                 (id_out_hazard_src1),
        .id_src2_in                 (id_out_hazard_src2),
        .id_two_src_in              (id_out_hazard_two_src),
        .exe_wb_en_in               (exe_out_wb_en),
        .exe_wb_reg_dest_in         (exe_out_wb_reg_dest),
        .mem_wb_en_in               (mem_out_wb_en),
        .mem_wb_reg_dest_in         (mem_out_wb_reg_dest),
        .exe_mem_r_en_in            (exe_out_mem_r_en),
        .id_instr_has_src1          (id_out_instr_has_src1),
        .use_forwarding_in          (use_forwarding),
        .hazard_out                 (hazard_out_hazard)
    );

    forwarding_unit forward_unit(
        .exe_src1_in                (exe_in_exe_src1),
        .exe_src2_in                (exe_in_exe_src2),
        .instr_has_src1_in          (frwd_in_instr_has_src1),
        .instr_has_src2_in          (frwd_in_instr_has_src2),
        .mem_wb_reg_dest_in         (mem_in_wb_reg_dest),
        .wb_wb_reg_dest_in          (wb_in_wb_reg_dest),
        .use_forwarding_in          (use_forwarding),
        .mem_wb_en_in               (mem_out_wb_en),
        .wb_wb_en_in                (wb_out_wb_en),
        .sel_normal_src1_out        (frwd_out_sel_normal_src1),
        .sel_normal_src2_out        (frwd_out_sel_normal_src2),
        .sel_mem_src1_out           (frwd_out_sel_mem_src1),
        .sel_mem_src2_out           (frwd_out_sel_mem_src2),
        .sel_wb_src1_out            (frwd_out_sel_wb_src1),
        .sel_wb_src2_out            (frwd_out_sel_wb_src2)
    );

    status_register sr_unit(
        .clk                        (clk),
        .rst                        (rst),
        .status_input               (exe_out_status_bits),
        .do_update_sr               (exe_out_do_update_sr),
        .status_output              (srreg_out_status_bits)
    );

    IF_stage if_stage_unit(
        .clk                        (clk),
        .rst                        (rst),
        .branch_taken_in            (exe_out_branch_taken),
        .freeze_in                  (hazard_out_hazard),
        .branch_address_in          (exe_out_branch_address),
        .pc_plus_four_out           (if_out_pc_plus_four),
        .instruction_mem_out        (if_out_instruction)
    );
    
    IF_stage_reg if_reg_unit (
        .clk                        (clk), 
        .rst                        (rst), 
        .flush                      (exe_out_branch_taken), 
        .freeze                     (hazard_out_hazard), 
        .pc_plus_four_in            (if_out_pc_plus_four), 
        .instruction_in             (if_out_instruction), 
        .pc_plus_four_out           (id_in_pc_plus_four), 
        .instruction_out            (id_in_instruction)
    );

    ID_stage id_stage_unit(
        .clk                        (clk),
        .rst                        (rst),
        .hazard_in                  (hazard_out_hazard),
        .wb_dest_in                 (wb_out_wb_reg_dest),
        .wb_value_in                (wb_out_wb_value),
        .wb_wb_en_in                (wb_out_wb_en),
        .instruction_in             (id_in_instruction),
        .status_bits_in             (srreg_out_status_bits),
        .pc_plus_four_in            (id_in_pc_plus_four),
        .instr_has_src1_out         (id_out_instr_has_src1),
        .instr_has_src2_out         (id_out_instr_has_src2),
        .wb_en_out                  (id_out_wb_en),
        .mem_r_en_out               (id_out_mem_r_en),
        .mem_w_en_out               (id_out_mem_w_en),
        .branch_taken_out           (id_out_branch_taken),
        .execute_command_out        (id_out_execute_command),
        .do_update_sr_out           (id_out_do_update_sr),
        .wb_reg_dest_out            (id_out_wb_reg_dest),
        .pc_plus_four_out           (id_out_pc_plus_four),
        .branch_immediate_out       (id_out_branch_immediate),
        .instr_is_immediate_out     (id_out_instr_is_immediate),
        .instr_shifter_opperand_out (id_out_instr_shifter_opperand),
        .val_rn_out                 (id_out_val_rn),
        .val_rm_out                 (id_out_val_rm),
        .hazard_two_src_out         (id_out_hazard_two_src),
        .hazard_src1_out            (id_out_hazard_src1),
        .hazard_src2_out            (id_out_hazard_src2),
        .exe_src1_out               (id_out_exe_src1),
        .exe_src2_out               (id_out_exe_src2)
    );

    ID_stage_reg id_reg_unit(
        .clk                        (clk),
        .rst                        (rst),
        .flush                      (exe_out_branch_taken),
        .wb_en_in                   (id_out_wb_en),
        .mem_r_en_in                (id_out_mem_r_en),
        .mem_w_en_in                (id_out_mem_w_en),
        .branch_taken_in            (id_out_branch_taken),
        .execute_command_in         (id_out_execute_command),
        .do_update_sr_in            (id_out_do_update_sr),
        .wb_reg_dest_in             (id_out_wb_reg_dest),
        .pc_plus_four_in            (id_out_pc_plus_four),
        .branch_immediate_in        (id_out_branch_immediate),
        .instr_is_immediate_in      (id_out_instr_is_immediate),
        .instr_shifter_opperand_in  (id_out_instr_shifter_opperand),
        .val_rn_in                  (id_out_val_rn),
        .val_rm_in                  (id_out_val_rm),
        .exe_src1_in                (id_out_exe_src1),
        .exe_src2_in                (id_out_exe_src2),
        .status_bits_in             (srreg_out_status_bits),
        .instr_has_src1_in          (id_out_instr_has_src1),
        .instr_has_src2_in          (id_out_instr_has_src2),
        .wb_en_out                  (exe_in_wb_en),
        .mem_r_en_out               (exe_in_mem_r_en),
        .mem_w_en_out               (exe_in_mem_w_en),
        .branch_taken_out           (exe_in_branch_taken),
        .execute_command_out        (exe_in_execute_command),
        .do_update_sr_out           (exe_in_do_update_sr),
        .wb_reg_dest_out            (exe_in_wb_reg_dest),
        .pc_plus_four_out           (exe_in_pc_plus_four),
        .branch_immediate_out       (exe_in_branch_immediate),
        .instr_is_immediate_out     (exe_in_instr_is_immediate),
        .instr_shifter_opperand_out (exe_in_instr_shifter_opperand),
        .val_rn_out                 (exe_in_val_rn),
        .val_rm_out                 (exe_in_val_rm),
        .status_bits_out            (exe_in_status_bits),
        .exe_src1_out               (exe_in_exe_src1),
        .exe_src2_out               (exe_in_exe_src2),
        .instr_has_src1_out         (frwd_in_instr_has_src1),
        .instr_has_src2_out         (frwd_in_instr_has_src2)
    );

    EXE_stage exe_stage_unit(
        .clk                        (clk),
        .rst                        (rst),
        .do_update_sr_in            (exe_in_do_update_sr),
        .wb_en_in                   (exe_in_wb_en),
        .mem_r_en_in                (exe_in_mem_r_en),
        .mem_w_en_in                (exe_in_mem_w_en),
        .branch_taken_in            (exe_in_branch_taken),
        .execute_command_in         (exe_in_execute_command),
        .wb_reg_dest_in             (exe_in_wb_reg_dest),
        .pc_plus_four_in            (exe_in_pc_plus_four),
        .branch_immediate_in        (exe_in_branch_immediate),
        .instr_shifter_opperand_in  (exe_in_instr_shifter_opperand),
        .instr_is_immediate_in      (exe_in_instr_is_immediate),
        .val_rn_in                  (exe_in_val_rn),
        .val_rm_in                  (exe_in_val_rm),
        .status_bits_in             (exe_in_status_bits),
        .frwd_mem_value_in          (mem_out_frwd_value),
        .frwd_wb_value_in           (wb_out_wb_value),
        .frwd_sel_normal_src1_in    (frwd_out_sel_normal_src1),
        .frwd_sel_normal_src2_in    (frwd_out_sel_normal_src2),
        .frwd_sel_mem_src1_in       (frwd_out_sel_mem_src1),
        .frwd_sel_mem_src2_in       (frwd_out_sel_mem_src2),
        .frwd_sel_wb_src1_in        (frwd_out_sel_wb_src1),
        .frwd_sel_wb_src2_in        (frwd_out_sel_wb_src2),
        .wb_reg_dest_out            (exe_out_wb_reg_dest),
        .do_update_sr_out           (exe_out_do_update_sr),
        .wb_en_out                  (exe_out_wb_en),
        .mem_r_en_out               (exe_out_mem_r_en),
        .mem_w_en_out               (exe_out_mem_w_en),
        .branch_address_out         (exe_out_branch_address),
        .branch_taken_out           (exe_out_branch_taken),
        .alu_result_out             (exe_out_alu_result),
        .val_rm_out                 (exe_out_val_rm),
        .status_bits_out            (exe_out_status_bits)
    );

    EXE_stage_reg exe_reg_unit(
        .clk                        (clk),
        .rst                        (rst),
        .wb_en_in                   (exe_out_wb_en), 
        .mem_r_en_in                (exe_out_mem_r_en), 
        .mem_w_en_in                (exe_out_mem_w_en), 
        .ALU_result_in              (exe_out_alu_result), 
        .wb_reg_dest_in             (exe_out_wb_reg_dest), 
        .val_rm_in                  (exe_out_val_rm), 
        .mem_r_en_out               (mem_in_mem_r_en), 
        .mem_w_en_out               (mem_in_mem_w_en), 
        .wb_en_out                  (mem_in_wb_en), 
        .ALU_result_out             (mem_in_alu_result),
        .wb_reg_dest_out            (mem_in_wb_reg_dest), 
        .val_rm_out                 (mem_in_val_rm)
    );

    MEM_stage mem_stage_unit(
        .clk                        (clk),
        .rst                        (rst),
        .wb_en_in                   (mem_in_wb_en),
        .mem_r_en_in                (mem_in_mem_r_en),
        .mem_w_en_in                (mem_in_mem_w_en),
        .alu_result_in              (mem_in_alu_result),
        .wb_reg_dest_in             (mem_in_wb_reg_dest),
        .val_rm_in                  (mem_in_val_rm),
        .wb_en_out                  (mem_out_wb_en),
        .mem_r_en_out               (mem_out_mem_r_en),
        .alu_result_out             (mem_out_alu_result),
        .data_memory_result_out     (mem_out_data_memory_result),
        .wb_reg_dest_out            (mem_out_wb_reg_dest),
        .frwd_mem_value_out         (mem_out_frwd_value)
    );

    MEM_stage_reg mem_reg_unit(
        .clk                        (clk),
        .rst                        (rst),
        .wb_en_in                   (mem_out_wb_en),
        .mem_r_en_in                (mem_out_mem_r_en),
        .alu_result_in              (mem_out_alu_result),
        .data_memory_result_in      (mem_out_data_memory_result),
        .wb_reg_dest_in             (mem_out_wb_reg_dest),
        .wb_en_out                  (wb_in_wb_en),
        .mem_r_en_out               (wb_in_mem_r_en),
        .alu_result_out             (wb_in_alu_result),
        .data_memory_result_out     (wb_in_data_memory_result),
        .wb_reg_dest_out            (wb_in_wb_reg_dest)
    );

    WB_stage wb_stage_unit(
        .clk                        (clk),
        .rst                        (rst),
        .wb_en_in                   (wb_in_wb_en),
        .mem_r_en_in                (wb_in_mem_r_en),
        .alu_result_in              (wb_in_alu_result),
        .data_memory_result_in      (wb_in_data_memory_result),
        .wb_reg_dest_in             (wb_in_wb_reg_dest),
        .wb_value_out               (wb_out_wb_value),
        .wb_en_out                  (wb_out_wb_en),
        .wb_reg_dest_out            (wb_out_wb_reg_dest)               
    );

endmodule