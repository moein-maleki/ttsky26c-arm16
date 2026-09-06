module MEM_stage_reg(
    input               clk,
    input               rst,
    input               wb_en_in,
    input               mem_r_en_in,
    input       [31:0]  alu_result_in,
    input       [31:0]  data_memory_result_in,
    input       [3:0]   wb_reg_dest_in,

    output reg          wb_en_out,
    output reg          mem_r_en_out,
    output reg  [31:0]  alu_result_out,
    output reg  [31:0]  data_memory_result_out,
    output reg  [3:0]   wb_reg_dest_out
);

    always @(posedge clk, posedge rst) begin
        if (rst) begin
            wb_en_out                       <= 0;
            mem_r_en_out                    <= 0;
            alu_result_out                  <= 0;
            data_memory_result_out          <= 0;
            wb_reg_dest_out                 <= 0;       
        end
        else begin
            wb_en_out                       <= wb_en_in;
            mem_r_en_out                    <= mem_r_en_in;
            alu_result_out                  <= alu_result_in;
            data_memory_result_out          <= data_memory_result_in;
            wb_reg_dest_out                 <= wb_reg_dest_in;    
        end
    end

endmodule