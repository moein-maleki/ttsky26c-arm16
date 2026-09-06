module WB_stage(
    input               clk,
    input               rst,
    input               wb_en_in,
    input               mem_r_en_in,
    input       [31:0]  alu_result_in,
    input       [31:0]  data_memory_result_in,
    input       [3:0]   wb_reg_dest_in,
    
    output      [31:0]  wb_value_out,
    output              wb_en_out,
    output      [3:0]   wb_reg_dest_out
);

    // control signals passing
    assign wb_reg_dest_out      = wb_reg_dest_in;
    assign wb_en_out            = wb_en_in;

    // mux
    assign wb_value_out         = (mem_r_en_in) ? (data_memory_result_in) : (alu_result_in);

endmodule