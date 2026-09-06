`define OPC_NOP     4'b0000 // 0
`define OPC_MOV     4'b1101 // 1
`define OPC_MVN     4'b1111 // 2
`define OPC_ADD     4'b0100 // 3
`define OPC_ADC     4'b0101 // 4
`define OPC_SUB     4'b0010 // 5
`define OPC_SBC     4'b0110 // 6
`define OPC_AND     4'b0000 // 7
`define OPC_ORR     4'b1100 // 8
`define OPC_EOR     4'b0001 // 9
`define OPC_CMP     4'b1010 // 10
`define OPC_TST     4'b1000 // 11
`define OPC_LDR     4'b0100 // 12
`define OPC_STR     4'b0100 // 13

`define MODE_ARITH  2'b00
`define MODE_LD_STR 2'b01
`define MODE_BR     2'b10

`define TYPE_NOP    4'b0000 // 0
`define TYPE_MOV    4'b0001 // 1
`define TYPE_MVN    4'b0010 // 2
`define TYPE_ADD    4'b0011 // 3
`define TYPE_ADC    4'b0100 // 4
`define TYPE_SUB    4'b0101 // 5
`define TYPE_SBC    4'b0110 // 6
`define TYPE_AND    4'b0111 // 7
`define TYPE_ORR    4'b1000 // 8
`define TYPE_EOR    4'b1001 // 9
`define TYPE_CMP    4'b1010 // 10
`define TYPE_TST    4'b1011 // 11
`define TYPE_LDR    4'b1100 // 12
`define TYPE_STR    4'b1101 // 13
`define TYPE_BR     4'b1110 // 14

`define EXECMD_NOP     4'b0000
`define EXECMD_MOV     4'b0001     // 0
`define EXECMD_MVN     4'b1001     // 1
`define EXECMD_ADD     4'b0010     // 2
`define EXECMD_ADC     4'b0011     // 3
`define EXECMD_SUB     4'b0100     // 4
`define EXECMD_SBC     4'b0101     // 5
`define EXECMD_AND     4'b0110     // 6
`define EXECMD_ORR     4'b0111     // 7
`define EXECMD_EOR     4'b1000     // 8
`define EXECMD_CMP     4'b0100     // 9
`define EXECMD_TST     4'b0110     // 10
`define EXECMD_LDR     4'b0010     // 11
`define EXECMD_STR     4'b0010     // 12
`define EXECMD_BR      4'b0000     // 13

module control_unit(
    input               instr_do_update_sr,
    input       [3:0]   instr_opcode,
    input       [1:0]   instr_mode,
    input               instr_is_immediate,
    
    output              instr_has_src1,
    output              instr_has_src2,
    output reg          wb_en,
    output reg          mem_r_en,
    output reg          mem_w_en,
    output reg          branch_taken,
    output reg  [3:0]   execute_command
);

    wire [3:0]      instr_type;

    assign instr_has_src1       = ~((instr_mode == `MODE_BR) | (instr_opcode == `OPC_MOV) | (instr_opcode == `OPC_MVN));
    assign instr_has_src2       = ~((instr_type == `TYPE_LDR) | (instr_mode == `MODE_BR) | (instr_is_immediate));  
        
    assign instr_type =
        ((instr_opcode == `OPC_MOV) & (instr_mode == `MODE_ARITH))                          ? (`TYPE_MOV) : // 1
        ((instr_opcode == `OPC_MVN) & (instr_mode == `MODE_ARITH))                          ? (`TYPE_MVN) : // 2
        ((instr_opcode == `OPC_ADD) & (instr_mode == `MODE_ARITH))                          ? (`TYPE_ADD) : // 3
        ((instr_opcode == `OPC_ADC) & (instr_mode == `MODE_ARITH))                          ? (`TYPE_ADC) : // 4
        ((instr_opcode == `OPC_SUB) & (instr_mode == `MODE_ARITH))                          ? (`TYPE_SUB) : // 5
        ((instr_opcode == `OPC_SBC) & (instr_mode == `MODE_ARITH))                          ? (`TYPE_SBC) : // 6
        ((instr_opcode == `OPC_AND) & (instr_mode == `MODE_ARITH))                          ? (`TYPE_AND) : // 7
        ((instr_opcode == `OPC_ORR) & (instr_mode == `MODE_ARITH))                          ? (`TYPE_ORR) : // 8
        ((instr_opcode == `OPC_EOR) & (instr_mode == `MODE_ARITH))                          ? (`TYPE_EOR) : // 9
        ((instr_opcode == `OPC_CMP) & (instr_mode == `MODE_ARITH))                          ? (`TYPE_CMP) : // 10
        ((instr_opcode == `OPC_TST) & (instr_mode == `MODE_ARITH))                          ? (`TYPE_TST) : // 11
        ((instr_opcode == `OPC_LDR) & (instr_mode == `MODE_LD_STR) & (instr_do_update_sr))  ? (`TYPE_LDR) : // 12
        ((instr_opcode == `OPC_STR) & (instr_mode == `MODE_LD_STR) & (~instr_do_update_sr)) ? (`TYPE_STR) : // 13
        ((instr_mode   == `MODE_BR))                                                        ? (`TYPE_BR) : // 14
        (`TYPE_NOP);

always @(*) begin
    {wb_en, mem_r_en, mem_w_en, branch_taken, execute_command} <= 0;
        case (instr_type)
            `TYPE_NOP:  {execute_command                      } <= {`EXECMD_NOP                  };
            `TYPE_MOV:  {execute_command,   wb_en             } <= {`EXECMD_MOV,     1'b1        };
            `TYPE_MVN:  {execute_command,   wb_en             } <= {`EXECMD_MVN,     1'b1        };
            `TYPE_ADD:  {execute_command,   wb_en             } <= {`EXECMD_ADD,     1'b1        }; 
            `TYPE_ADC:  {execute_command,   wb_en             } <= {`EXECMD_ADC,     1'b1        };
            `TYPE_SUB:  {execute_command,   wb_en             } <= {`EXECMD_SUB,     1'b1        };
            `TYPE_SBC:  {execute_command,   wb_en             } <= {`EXECMD_SBC,     1'b1        };
            `TYPE_AND:  {execute_command,   wb_en             } <= {`EXECMD_AND,     1'b1        };
            `TYPE_ORR:  {execute_command,   wb_en             } <= {`EXECMD_ORR,     1'b1        };
            `TYPE_EOR:  {execute_command,   wb_en             } <= {`EXECMD_EOR,     1'b1        };
            `TYPE_CMP:  {execute_command                      } <= {`EXECMD_CMP                  };
            `TYPE_TST:  {execute_command                      } <= {`EXECMD_TST                  };
            `TYPE_LDR:  {execute_command,   wb_en,   mem_r_en } <= {`EXECMD_LDR,     1'b1,   1'b1};
            `TYPE_STR:  {execute_command,   mem_w_en          } <= {`EXECMD_STR,     1'b1        };
            `TYPE_BR:   {execute_command,   branch_taken      } <= {`EXECMD_BR,      1'b1        };
            default:    {wb_en, mem_r_en, mem_w_en, branch_taken, execute_command} <= 0;
        endcase
    end

endmodule