// 16-bit PC. The 32-bit ARM instruction is fetched externally as two consecutive 16-bit words.
module IF_stage(
    input               clk,
    input               rst,
    input               freeze_in,
    input               branch_taken_in,
    input       [15:0]  branch_address_in,
    input       [31:0]  instruction_in,     // from the fetch unit
    input               instr_ready_in,
    output      [15:0]  pc_out,             // to the fetch unit
    output              instr_req_out,
    output      [15:0]  pc_plus_four_out,
    output reg  [31:0]  instruction_mem_out
);
    reg  [15:0] pc_reg_out;
    wire [15:0] pc_reg_in;

    assign pc_reg_in        = (branch_taken_in) ? (branch_address_in) : (pc_plus_four_out);
    assign pc_plus_four_out = pc_reg_out + 16'd4;
    assign pc_out           = pc_reg_out;
    assign instr_req_out    = ~freeze_in;

    always @(posedge clk) begin
        if (rst)                 pc_reg_out <= 0;
        else if (branch_taken_in) pc_reg_out <= pc_reg_in;
        else if (freeze_in)      pc_reg_out <= pc_reg_out;
        else if (instr_ready_in) pc_reg_out <= pc_reg_in;
    end

    always @(posedge clk) begin
        if (rst) instruction_mem_out <= 32'b0;
        else if (instr_ready_in) instruction_mem_out <= instruction_in;
    end
endmodule
