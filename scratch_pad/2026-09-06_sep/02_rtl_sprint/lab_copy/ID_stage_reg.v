module ID_stage_reg(
    input               clk,
    input               rst,
    input               flush,
    input               wb_en_in,
    input               mem_r_en_in,
    input               mem_w_en_in,
    input               branch_taken_in,
    input       [3:0]   execute_command_in,
    input               do_update_sr_in,
    input       [3:0]   wb_reg_dest_in,
    input       [31:0]  pc_plus_four_in,
    input       [31:0]  branch_immediate_in,
    input       [11:0]  instr_shifter_opperand_in,
    input               instr_is_immediate_in,
    input       [31:0]  val_rn_in,
    input       [31:0]  val_rm_in,
    input       [3:0]   status_bits_in,
    input       [3:0]   exe_src1_in,
    input       [3:0]   exe_src2_in,
    input               instr_has_src1_in,
    input               instr_has_src2_in,

    output reg          wb_en_out,
    output reg          mem_r_en_out,
    output reg          mem_w_en_out,
    output reg          branch_taken_out,
    output reg  [3:0]   execute_command_out,
    output reg          do_update_sr_out,
    output reg  [3:0]   wb_reg_dest_out,
    output reg  [31:0]  pc_plus_four_out,
    output reg  [31:0]  branch_immediate_out,
    output reg  [11:0]  instr_shifter_opperand_out,
    output reg          instr_is_immediate_out,
    output reg  [31:0]  val_rn_out,
    output reg  [31:0]  val_rm_out,
    output reg  [3:0]   status_bits_out,
    output reg  [3:0]   exe_src1_out,
    output reg  [3:0]   exe_src2_out,
    output reg          instr_has_src1_out,
    output reg          instr_has_src2_out
);

    wire clear;

    assign clear = flush | rst;

    always @(posedge clk) begin
        if (clear) begin
            wb_en_out                       <= 0;  
            mem_r_en_out                    <= 0;    
            mem_w_en_out                    <= 0;    
            branch_taken_out                <= 0;        
            execute_command_out             <= 0;        
            do_update_sr_out                <= 0;        
            wb_reg_dest_out                 <= 0;    
            pc_plus_four_out                <= 0;        
            branch_immediate_out            <= 0;            
            instr_shifter_opperand_out      <= 0;
            instr_is_immediate_out          <= 0;
            val_rn_out                      <= 0;
            val_rm_out                      <= 0;
            status_bits_out                 <= 0;
            exe_src1_out                    <= 0;
            exe_src2_out                    <= 0;
            instr_has_src1_out              <= 0;
            instr_has_src2_out              <= 0;
        end
        else begin
            wb_en_out                       <= wb_en_in;  
            mem_r_en_out                    <= mem_r_en_in;    
            mem_w_en_out                    <= mem_w_en_in;    
            branch_taken_out                <= branch_taken_in;        
            execute_command_out             <= execute_command_in;        
            do_update_sr_out                <= do_update_sr_in;        
            wb_reg_dest_out                 <= wb_reg_dest_in;    
            pc_plus_four_out                <= pc_plus_four_in;        
            branch_immediate_out            <= branch_immediate_in;            
            instr_shifter_opperand_out      <= instr_shifter_opperand_in;
            instr_is_immediate_out          <= instr_is_immediate_in;
            val_rn_out                      <= val_rn_in;
            val_rm_out                      <= val_rm_in;
            status_bits_out                 <= status_bits_in;
            exe_src1_out                    <= exe_src1_in;
            exe_src2_out                    <= exe_src2_in;
            instr_has_src1_out              <= instr_has_src1_in;
            instr_has_src2_out              <= instr_has_src2_in;
        end
    end

endmodule