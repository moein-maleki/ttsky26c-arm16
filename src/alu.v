// Sixteen-bit ALU with the ARM flag definition (spec 3.1): N = result[15], Z = result == 0,
// C = carry out on addition and NOT borrow on subtraction, V = signed overflow. One adder serves ADD,
// ADC, SUB and SBC (subtraction adds the inverted operand with the carry-in rule of the ARM
// definition). Logical operations and MOV/MVN report arith_out = 0 so the datapath keeps C and V
// (plan D1).
`default_nettype none
module alu (
    input  wire [15:0] operand_a_in,
    input  wire [15:0] operand_b_in,
    input  wire [3:0]  command_in,
    input  wire        carry_in,
    output reg  [15:0] result_out,
    output wire        carry_out,
    output wire        overflow_out,
    output reg         arith_out,
    output wire        negative_out,
    output wire        zero_out
);
    localparam [3:0] CMD_NOP = 4'b0000;
    localparam [3:0] CMD_MOV = 4'b0001;
    localparam [3:0] CMD_ADD = 4'b0010;
    localparam [3:0] CMD_ADC = 4'b0011;
    localparam [3:0] CMD_SUB = 4'b0100;
    localparam [3:0] CMD_SBC = 4'b0101;
    localparam [3:0] CMD_AND = 4'b0110;
    localparam [3:0] CMD_ORR = 4'b0111;
    localparam [3:0] CMD_EOR = 4'b1000;
    localparam [3:0] CMD_MVN = 4'b1001;

    wire        subtract;
    wire        adder_carry_in;
    wire [15:0] operand_b_eff;
    wire [16:0] sum;

    assign subtract       = (command_in == CMD_SUB) | (command_in == CMD_SBC);
    assign adder_carry_in = (command_in == CMD_SUB) ? 1'b1 : ((command_in == CMD_ADD) ? 1'b0 : carry_in);
    assign operand_b_eff  = subtract ? ~operand_b_in : operand_b_in;
    assign sum            = {1'b0, operand_a_in} + {1'b0, operand_b_eff} + {16'h0000, adder_carry_in};
    assign carry_out      = sum[16];
    assign overflow_out   = (operand_a_in[15] == operand_b_eff[15]) & (sum[15] != operand_a_in[15]);
    assign negative_out   = result_out[15];
    assign zero_out       = (result_out == 16'h0000);

    always @* begin
        result_out = 16'h0000;
        arith_out  = 1'b0;
        case (command_in)
            CMD_MOV: result_out = operand_b_in;
            CMD_MVN: result_out = ~operand_b_in;
            CMD_AND: result_out = operand_a_in & operand_b_in;
            CMD_ORR: result_out = operand_a_in | operand_b_in;
            CMD_EOR: result_out = operand_a_in ^ operand_b_in;
            CMD_ADD, CMD_ADC, CMD_SUB, CMD_SBC: begin
                result_out = sum[15:0];
                arith_out  = 1'b1;
            end
            default: result_out = 16'h0000;
        endcase
    end
endmodule
`default_nettype wire
