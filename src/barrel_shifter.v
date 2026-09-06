// Operand 2 of the data-processing and load/store instructions on 16 bits (spec 3.1, plan D1):
// immediate form: imm8 rotated right by 2 * rot in a 16-bit ring; register form: Rm shifted by the
// 5-bit immediate with LSL, LSR, ASR, ROR (amounts of 16 or more give 0, sign fill, or wrap);
// memory form: the 12-bit offset zero-extended (the direction bit selects ADD or SUB in the decoder).
`default_nettype none
module barrel_shifter (
    input  wire [15:0] value_in,
    input  wire [11:0] operand2_in,
    input  wire        immediate_in,
    input  wire        memory_in,
    output reg  [15:0] result_out
);
    wire [3:0]  rotate_amount;
    wire [7:0]  imm8;
    wire [4:0]  shift_amount;
    wire [1:0]  shift_type;
    wire [31:0] imm_rail;
    wire [15:0] imm_rotated;
    wire [31:0] value_rail;
    wire [15:0] value_rotated;
    wire [15:0] value_lsl;
    wire [15:0] value_lsr;
    wire [15:0] value_asr;
    wire [15:0] sign_fill;

    assign rotate_amount = operand2_in[11:8];
    assign imm8          = operand2_in[7:0];
    assign shift_amount  = operand2_in[11:7];
    assign shift_type    = operand2_in[6:5];
    assign imm_rail      = {{8{1'b0}}, imm8, {8{1'b0}}, imm8} >> {rotate_amount[2:0], 1'b0};
    assign imm_rotated   = imm_rail[15:0];
    assign value_rail    = {value_in, value_in} >> shift_amount[3:0];
    assign value_rotated = value_rail[15:0];
    assign value_lsl     = value_in << shift_amount[3:0];
    assign value_lsr     = value_in >> shift_amount[3:0];
    assign sign_fill     = {16{value_in[15]}};
    assign value_asr     = (value_lsr) | (sign_fill << (5'd16 - {1'b0, shift_amount[3:0]}));

    always @* begin
        result_out = 16'h0000;
        if (memory_in) begin
            result_out = {4'b0000, operand2_in};
        end else if (immediate_in) begin
            result_out = imm_rotated;
        end else begin
            case (shift_type)
                2'b00: result_out = shift_amount[4] ? 16'h0000 : value_lsl;
                2'b01: result_out = shift_amount[4] ? 16'h0000 : value_lsr;
                2'b10: result_out = shift_amount[4] ? sign_fill : (shift_amount[3:0] == 4'd0 ? value_in : value_asr);
                default: result_out = value_rotated;
            endcase
        end
    end
endmodule
`default_nettype wire
