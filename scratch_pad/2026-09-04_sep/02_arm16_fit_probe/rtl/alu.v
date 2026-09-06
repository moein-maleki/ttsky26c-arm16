`define EXECMD_NOP              4'b0000
`define EXECMD_MOV              4'b0001     // 1
`define EXECMD_ADD_LDR_STR      4'b0010     // 2
`define EXECMD_ADC              4'b0011     // 3
`define EXECMD_SUB_CMP          4'b0100     // 4
`define EXECMD_SBC              4'b0101     // 5
`define EXECMD_AND_TST          4'b0110     // 6
`define EXECMD_ORR              4'b0111     // 7
`define EXECMD_EOR              4'b1000     // 8
`define EXECMD_MVN              4'b1001     // 9

module alu(
    input       signed  [15:0]  alu_in_1,
    input       signed  [15:0]  alu_in_2,
    input               [3:0]   execute_command,
    input               [3:0]   status_bits_in,

    output reg  signed  [15:0]  alu_result,
    output              [3:0]   status_bits_out
);

    wire    sr_bit_C_in;
    reg     sr_bit_C_out;
    wire    sr_bit_N_out;
    wire    sr_bit_Z_out;
    wire    sr_bit_V_out;

    assign sr_bit_C_in      = status_bits_in[1];
    assign sr_bit_N_out     = alu_result[31];
    assign sr_bit_Z_out     = ~(|alu_result);
    assign sr_bit_V_out     =
        ((~(alu_in_1[31] ^ alu_in_2[31])) ^ (alu_result[31])) & (execute_command == `EXECMD_ADD_LDR_STR) |
        (((alu_in_1[31] ^ alu_in_2[31]) & (alu_result[31] == alu_in_2[31])) & (execute_command == `EXECMD_SUB_CMP));
    
    assign status_bits_out  = {sr_bit_N_out, sr_bit_Z_out, sr_bit_C_out, sr_bit_V_out};

    always @(*) begin
        alu_result      = 16'bx;
        sr_bit_C_out    = sr_bit_C_in;
        case (execute_command)
            `EXECMD_NOP:                alu_result                  = 16'b0;
            `EXECMD_MOV:                alu_result                  = alu_in_2;
            `EXECMD_ADD_LDR_STR:        {sr_bit_C_out, alu_result}  = alu_in_1 + alu_in_2;
            `EXECMD_ADC:                {sr_bit_C_out, alu_result}  = alu_in_1 + alu_in_2 + {31'b0, sr_bit_C_in};
            `EXECMD_SUB_CMP:            {sr_bit_C_out, alu_result}  = alu_in_1 - alu_in_2;
            `EXECMD_SBC:                {sr_bit_C_out, alu_result}  = alu_in_1 - alu_in_2 - {31'b0, ~sr_bit_C_in};
            `EXECMD_AND_TST:            alu_result                  = alu_in_1 & alu_in_2;
            `EXECMD_ORR:                alu_result                  = alu_in_1 | alu_in_2;
            `EXECMD_EOR:                alu_result                  = alu_in_1 ^ alu_in_2;
            `EXECMD_MVN:                alu_result                  = ~alu_in_2;
            default:                    alu_result                  = 16'bx;
        endcase
    end 

endmodule