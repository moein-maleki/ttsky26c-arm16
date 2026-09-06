module hazard_detection(
    input       [3:0]   id_src1_in,
    input       [3:0]   id_src2_in,
    input               id_two_src_in,
    input               id_instr_has_src1,
    input               exe_wb_en_in,
    input       [3:0]   exe_wb_reg_dest_in,
    input               mem_wb_en_in,
    input       [3:0]   mem_wb_reg_dest_in,
    input               exe_mem_r_en_in,
    input               use_forwarding_in,

    output              hazard_out
);

    assign hazard_out =
        (   
            (~use_forwarding_in) & (
                (
                    (exe_wb_en_in) & ((
                    (exe_wb_reg_dest_in == id_src1_in) & (id_instr_has_src1)
                    ) | (
                    (exe_wb_reg_dest_in == id_src2_in) & (id_two_src_in)))
                ) | (
                    (mem_wb_en_in) & ((
                    (mem_wb_reg_dest_in == id_src1_in) & (id_instr_has_src1)
                    ) | (
                    (mem_wb_reg_dest_in == id_src2_in) & (id_two_src_in)))
                )
            )
        ) | (
            (use_forwarding_in) & (exe_mem_r_en_in) & (
                ((exe_wb_reg_dest_in == id_src1_in) & (id_instr_has_src1)) |
                ((exe_wb_reg_dest_in == id_src2_in) & (id_two_src_in))
            )
        );

endmodule