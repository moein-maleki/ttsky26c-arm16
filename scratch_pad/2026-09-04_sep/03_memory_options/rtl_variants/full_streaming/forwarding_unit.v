module forwarding_unit(
    input       [3:0]   exe_src1_in,
    input       [3:0]   exe_src2_in,
    input       [3:0]   mem_wb_reg_dest_in,
    input       [3:0]   wb_wb_reg_dest_in,
    input               use_forwarding_in,
    input               instr_has_src1_in,
    input               instr_has_src2_in,
    input               mem_wb_en_in,
    input               wb_wb_en_in,

    output              sel_normal_src1_out,
    output              sel_normal_src2_out,
    output              sel_mem_src1_out,
    output              sel_mem_src2_out,
    output              sel_wb_src1_out,
    output              sel_wb_src2_out
);

    wire mem_data_dependency_src1;
    wire mem_data_dependency_src2;
    wire wb_data_dependency_src1;
    wire wb_data_dependency_src2;

    assign mem_data_dependency_src1 = (exe_src1_in == mem_wb_reg_dest_in) & (instr_has_src1_in) & (mem_wb_en_in);
    assign mem_data_dependency_src2 = (exe_src2_in == mem_wb_reg_dest_in) & (instr_has_src2_in) & (mem_wb_en_in);

    assign wb_data_dependency_src1  = (exe_src1_in == wb_wb_reg_dest_in) & (instr_has_src1_in) & (wb_wb_en_in);
    assign wb_data_dependency_src2  = (exe_src2_in == wb_wb_reg_dest_in) & (instr_has_src2_in) & (wb_wb_en_in);

    assign sel_mem_src1_out         = (mem_data_dependency_src1) & (use_forwarding_in);
    assign sel_mem_src2_out         = (mem_data_dependency_src2) & (use_forwarding_in);
    assign sel_wb_src1_out          = (wb_data_dependency_src1) & (use_forwarding_in);
    assign sel_wb_src2_out          = (wb_data_dependency_src2) & (use_forwarding_in);

    assign sel_normal_src1_out      =
        (~use_forwarding_in) ? (1'b1) :
        (use_forwarding_in) ? ((~sel_mem_src1_out) & (~sel_wb_src1_out)) : 1'b0;
        
    assign sel_normal_src2_out      =
        (~use_forwarding_in) ? (1'b1) :
        (use_forwarding_in) ? ((~sel_mem_src2_out) & (~sel_wb_src2_out)) : 1'b0;

endmodule