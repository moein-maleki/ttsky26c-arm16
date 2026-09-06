`define COND_EQ     4'b0000
`define COND_NE     4'b0001
`define COND_CS_HS  4'b0010
`define COND_CC_LO  4'b0011
`define COND_MI     4'b0100
`define COND_PL     4'b0101
`define COND_VS     4'b0110
`define COND_VC     4'b0111
`define COND_HI     4'b1000
`define COND_LS     4'b1001
`define COND_GE     4'b1010
`define COND_LT     4'b1011
`define COND_GT     4'b1100
`define COND_LE     4'b1101
`define COND_AL     4'b1110

module condition_check(
    input       [3:0]   instr_condition,
    input       [3:0]   status_register,

    output reg          condition_is_met
);

    wire sr_bit_N;
    wire sr_bit_Z;
    wire sr_bit_C;
    wire sr_bit_V;

    assign sr_bit_N = status_register[3];
    assign sr_bit_Z = status_register[2];
    assign sr_bit_C = status_register[1];
    assign sr_bit_V = status_register[0];

    always @(*) begin
        condition_is_met <= 0;
        case (instr_condition)
            `COND_EQ:       condition_is_met <= (sr_bit_Z);
            `COND_NE:       condition_is_met <= (~sr_bit_Z);
            `COND_CS_HS:    condition_is_met <= (sr_bit_C);
            `COND_CC_LO:    condition_is_met <= (~sr_bit_C);
            `COND_MI:       condition_is_met <= (sr_bit_N);
            `COND_PL:       condition_is_met <= (~sr_bit_N);
            `COND_VS:       condition_is_met <= (sr_bit_V);
            `COND_VC:       condition_is_met <= (~sr_bit_V);
            `COND_HI:       condition_is_met <= (sr_bit_C) & (~sr_bit_Z);
            `COND_LS:       condition_is_met <= (~sr_bit_C) | (sr_bit_Z);
            `COND_GE:       condition_is_met <= (sr_bit_N) == (sr_bit_V);
            `COND_LT:       condition_is_met <= (sr_bit_N) != (sr_bit_V);
            `COND_GT:       condition_is_met <= (~sr_bit_Z) & ((sr_bit_N) == (sr_bit_V));
            `COND_LE:       condition_is_met <= (sr_bit_Z) | ((sr_bit_N) != (sr_bit_V));
            `COND_AL:       condition_is_met <= 1'b1;
            default:        condition_is_met <= 0;
        endcase
    end

endmodule