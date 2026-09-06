// Memory stage with the cache removed. Issues a request to the external serial memory and stalls
// the pipeline until it completes. Forwarding, hazard and write-back behaviour are unchanged.
module MEM_stage(
    input               clk,
    input               rst,
    input               wb_en_in,
    input               mem_r_en_in,
    input               mem_w_en_in,
    input       [15:0]  alu_result_in,
    input       [3:0]   wb_reg_dest_in,
    input       [15:0]  val_rm_in,

    output              wb_en_out,
    output              mem_r_en_out,
    output      [15:0]  alu_result_out,
    output      [15:0]  data_memory_result_out,
    output      [3:0]   wb_reg_dest_out,
    output      [15:0]  frwd_mem_value_out,
    output              stage_busy_out,

    // generic memory port to the serial memory controller
    output      [15:0]  mem_addr_out,
    output      [15:0]  mem_wdata_out,
    output              mem_we_out,
    output              mem_re_out,
    input       [15:0]  mem_rdata_in,
    input               mem_ready_in
);
    wire [15:0] memory_address;
    wire        access_pending;

    assign wb_en_out              = wb_en_in;
    assign mem_r_en_out           = mem_r_en_in;
    assign alu_result_out         = alu_result_in;
    assign wb_reg_dest_out        = wb_reg_dest_in;
    assign frwd_mem_value_out     = alu_result_out;

    assign memory_address         = alu_result_in - 16'd1024;
    assign mem_addr_out           = {1'b0, memory_address[15:1]};
    assign mem_wdata_out          = val_rm_in;
    assign mem_we_out             = mem_w_en_in;
    assign mem_re_out             = mem_r_en_in;
    assign data_memory_result_out = mem_rdata_in;

    assign access_pending         = mem_r_en_in | mem_w_en_in;
    assign stage_busy_out         = access_pending & ~mem_ready_in;
endmodule
