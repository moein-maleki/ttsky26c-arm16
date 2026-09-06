module IF_stage_reg (    
    input               clk,
    input               rst,
    input               flush,
    input               freeze,

    input       [31:0]  pc_plus_four_in,
    input       [31:0]  instruction_in,

    output reg  [31:0]  pc_plus_four_out,
    output reg  [31:0]  instruction_out
);

    wire clear;

    assign clear = rst | flush;

    always @(posedge clk) begin
        if (clear)          {pc_plus_four_out, instruction_out} <= 64'b0;
        else if(freeze)     {pc_plus_four_out, instruction_out} <= {pc_plus_four_out, instruction_out};
        else                {pc_plus_four_out, instruction_out} <= {pc_plus_four_in, instruction_in};
    end

endmodule