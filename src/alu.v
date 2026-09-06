// Sixteen-bit ALU with the ARM flag definition (spec 3.1): N = result[15], Z = result == 0,
// C = carry out on addition and NOT borrow on subtraction, V = signed overflow. Logical operations
// and MOV/MVN report arith_out = 0 so the datapath keeps C and V (plan D1).
`default_nettype none
module alu (
    input  wire [15:0] operand_a_in,
    input  wire [15:0] operand_b_in,
    input  wire [3:0]  command_in,
    input  wire        carry_in,
    output reg  [15:0] result_out,
    output reg         carry_out,
    output reg         overflow_out,
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

    wire [15:0] operand_b_inverted;
    wire [16:0] sum_add;
    wire [16:0] sum_adc;
    wire [16:0] sum_sub;
    wire [16:0] sum_sbc;

    assign operand_b_inverted = ~operand_b_in;
    assign sum_add = {1'b0, operand_a_in} + {1'b0, operand_b_in};
    assign sum_adc = {1'b0, operand_a_in} + {1'b0, operand_b_in} + {16'h0000, carry_in};
    assign sum_sub = {1'b0, operand_a_in} + {1'b0, operand_b_inverted} + 17'h00001;
    assign sum_sbc = {1'b0, operand_a_in} + {1'b0, operand_b_inverted} + {16'h0000, carry_in};
    assign negative_out = result_out[15];
    assign zero_out     = (result_out == 16'h0000);

    always @* begin
        result_out   = 16'h0000;
        carry_out    = 1'b0;
        overflow_out = 1'b0;
        arith_out    = 1'b0;
        case (command_in)
            CMD_MOV: result_out = operand_b_in;
            CMD_MVN: result_out = operand_b_inverted;
            CMD_AND: result_out = operand_a_in & operand_b_in;
            CMD_ORR: result_out = operand_a_in | operand_b_in;
            CMD_EOR: result_out = operand_a_in ^ operand_b_in;
            CMD_ADD: begin
                result_out   = sum_add[15:0];
                carry_out    = sum_add[16];
                overflow_out = (operand_a_in[15] == operand_b_in[15]) & (sum_add[15] != operand_a_in[15]);
                arith_out    = 1'b1;
            end
            CMD_ADC: begin
                result_out   = sum_adc[15:0];
                carry_out    = sum_adc[16];
                overflow_out = (operand_a_in[15] == operand_b_in[15]) & (sum_adc[15] != operand_a_in[15]);
                arith_out    = 1'b1;
            end
            CMD_SUB: begin
                result_out   = sum_sub[15:0];
                carry_out    = sum_sub[16];
                overflow_out = (operand_a_in[15] != operand_b_in[15]) & (sum_sub[15] != operand_a_in[15]);
                arith_out    = 1'b1;
            end
            CMD_SBC: begin
                result_out   = sum_sbc[15:0];
                carry_out    = sum_sbc[16];
                overflow_out = (operand_a_in[15] != operand_b_in[15]) & (sum_sbc[15] != operand_a_in[15]);
                arith_out    = 1'b1;
            end
            default: result_out = 16'h0000;
        endcase
    end
endmodule
`default_nettype wire
