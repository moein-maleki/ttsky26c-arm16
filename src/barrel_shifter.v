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
    wire [3:0]  amount;
    wire [3:0]  rotate_by;
    wire [31:0] imm_rail;
    wire [15:0] imm_rotated;
    wire [31:0] value_rail;
    wire [15:0] rotated;
    wire [15:0] keep_high_mask;
    wire [15:0] keep_low_mask;
    wire        big_shift;
    wire        sign;

    assign rotate_amount  = operand2_in[11:8];
    assign imm8           = operand2_in[7:0];
    assign shift_amount   = operand2_in[11:7];
    assign shift_type     = operand2_in[6:5];
    assign amount         = shift_amount[3:0];
    assign big_shift      = shift_amount[4];
    assign sign           = value_in[15];
    assign imm_rail       = {{8{1'b0}}, imm8, {8{1'b0}}, imm8} >> {rotate_amount[2:0], 1'b0};
    assign imm_rotated    = imm_rail[15:0];
    // one rotator serves every register form: rotate right by `amount` for LSR, ASR and ROR, and by
    // 16 - amount for LSL; the masks clear the bits a true shift would drop
    assign rotate_by      = (shift_type == 2'b00) ? (4'd0 - amount) : amount;
    assign value_rail     = {value_in, value_in} >> rotate_by;
    assign rotated        = value_rail[15:0];
    assign keep_high_mask = 16'hFFFF << amount;      // LSL: the low `amount` bits become 0
    assign keep_low_mask  = 16'hFFFF >> amount;      // LSR, ASR: the high `amount` bits become 0 or the sign

    always @* begin
        result_out = 16'h0000;
        if (memory_in) begin
            result_out = {4'b0000, operand2_in};
        end else if (immediate_in) begin
            result_out = imm_rotated;
        end else begin
            case (shift_type)
                2'b00:   result_out = big_shift ? 16'h0000 : (rotated & keep_high_mask);
                2'b01:   result_out = big_shift ? 16'h0000 : (rotated & keep_low_mask);
                2'b10:   result_out = big_shift ? {16{sign}} : ((rotated & keep_low_mask) | (sign ? ~keep_low_mask : 16'h0000));
                default: result_out = rotated;
            endcase
        end
    end
endmodule
`default_nettype wire
