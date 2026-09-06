module MEM_stage(
    input               clk,
    input               rst,
    input               wb_en_in,
    input               mem_r_en_in,
    input               mem_w_en_in,
    input       [31:0]  alu_result_in,
    input       [3:0]   wb_reg_dest_in,  
    input       [31:0]  val_rm_in,

    output              wb_en_out,
    output              mem_r_en_out,
    output      [31:0]  alu_result_out,
    output      [31:0]  data_memory_result_out,
    output      [3:0]   wb_reg_dest_out,
    output      [31:0]  frwd_mem_value_out
);

    wire [31:0] memory_address;
    wire [31:0] aligned_address;

    reg [7:0] memory_element [0:255];

    // control signal passing
    assign wb_en_out                    = wb_en_in;
    assign mem_r_en_out                 = mem_r_en_in;
    assign alu_result_out               = alu_result_in;
    assign wb_reg_dest_out              = wb_reg_dest_in;

    // forwarding
    assign frwd_mem_value_out           = alu_result_out; 
    // assign frwd_mem_value_out =
    //     (mem_r_en_in) ? (data_memory_result_out) :
    //     (~mem_r_en_in) ? (alu_result_out) : 32'bz;

    // memory
    always@(posedge clk) begin
        if(mem_w_en_in)
            {memory_element[aligned_address+3], memory_element[aligned_address+2], memory_element[aligned_address+1], memory_element[aligned_address]} <= val_rm_in;
    end

    assign memory_address = alu_result_in - 32'd1024;
    assign aligned_address = {memory_address[31:2], 2'b0};
    assign data_memory_result_out = (mem_r_en_in) ? (
        {memory_element[aligned_address+3], memory_element[aligned_address+2],
        memory_element[aligned_address+1], memory_element[aligned_address]}) : (32'bz);

endmodule