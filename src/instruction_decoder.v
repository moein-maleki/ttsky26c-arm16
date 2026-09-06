// Decode of the 32-bit ARM word into the subset of spec 3.1. Everything outside the subset decodes as a
// NOP: no register write, no memory access, no branch, no flag change (this includes the MRS and MSR
// encodings, which are TST and CMP opcodes with S = 0, and loads or stores of r15). Condition 1111 is the
// bubble marker and reports valid_out = 0.
`default_nettype none
module instruction_decoder (
    input  wire [31:0] instr_in,
    output reg         valid_out,
    output wire [3:0]  cond_out,
    output reg         is_load_out,
    output reg         is_store_out,
    output reg         is_branch_out,
    output reg         link_out,
    output reg         wb_en_out,
    output reg         set_flags_out,
    output reg  [3:0]  command_out,
    output reg         immediate_out,
    output reg         memory_out,
    output reg  [3:0]  dest_out,
    output reg         dest_is_pc_out,
    output reg  [3:0]  src1_out,
    output reg  [3:0]  src2_out,
    output reg         has_src1_out,
    output reg         has_src2_out,
    output wire [11:0] operand2_out,
    output wire [23:0] branch_imm_out
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

    localparam [3:0] OPC_AND = 4'b0000;
    localparam [3:0] OPC_EOR = 4'b0001;
    localparam [3:0] OPC_SUB = 4'b0010;
    localparam [3:0] OPC_ADD = 4'b0100;
    localparam [3:0] OPC_ADC = 4'b0101;
    localparam [3:0] OPC_SBC = 4'b0110;
    localparam [3:0] OPC_TST = 4'b1000;
    localparam [3:0] OPC_CMP = 4'b1010;
    localparam [3:0] OPC_ORR = 4'b1100;
    localparam [3:0] OPC_MOV = 4'b1101;
    localparam [3:0] OPC_MVN = 4'b1111;

    wire [1:0] mode;
    wire       bit_i;
    wire [3:0] opcode;
    wire       bit_s;
    wire [3:0] field_rn;
    wire [3:0] field_rd;
    wire [3:0] field_rm;
    wire       bit_4;
    wire       bit_p;
    wire       bit_u;
    wire       bit_b;
    wire       bit_w;
    wire       bit_l;
    wire       dp_form_ok;
    wire       ldst_form_ok;

    assign mode           = instr_in[27:26];
    assign bit_i          = instr_in[25];
    assign opcode         = instr_in[24:21];
    assign bit_s          = instr_in[20];
    assign field_rn       = instr_in[19:16];
    assign field_rd       = instr_in[15:12];
    assign field_rm       = instr_in[3:0];
    assign bit_4          = instr_in[4];
    assign bit_p          = instr_in[24];
    assign bit_u          = instr_in[23];
    assign bit_b          = instr_in[22];
    assign bit_w          = instr_in[21];
    assign bit_l          = instr_in[20];
    assign cond_out       = instr_in[31:28];
    assign operand2_out   = instr_in[11:0];
    assign branch_imm_out = instr_in[23:0];
    assign dp_form_ok     = (mode == 2'b00) & (bit_i | ~bit_4) & ~((opcode[3:2] == 2'b10) & ~bit_s);
    assign ldst_form_ok   = (mode == 2'b01) & ~bit_i & bit_p & ~bit_b & ~bit_w & (field_rd != 4'd15);

    always @* begin
        valid_out      = (instr_in[31:28] != 4'b1111);
        is_load_out    = 1'b0;
        is_store_out   = 1'b0;
        is_branch_out  = 1'b0;
        link_out       = 1'b0;
        wb_en_out      = 1'b0;
        set_flags_out  = 1'b0;
        command_out    = CMD_NOP;
        immediate_out  = 1'b0;
        memory_out     = 1'b0;
        dest_out       = field_rd;
        dest_is_pc_out = 1'b0;
        src1_out       = field_rn;
        src2_out       = field_rm;
        has_src1_out   = 1'b0;
        has_src2_out   = 1'b0;
        if (dp_form_ok) begin
            immediate_out = bit_i;
            set_flags_out = bit_s;
            has_src1_out  = 1'b1;
            has_src2_out  = ~bit_i;
            wb_en_out     = (field_rd != 4'd15);
            dest_is_pc_out = (field_rd == 4'd15);
            case (opcode)
                OPC_AND: command_out = CMD_AND;
                OPC_EOR: command_out = CMD_EOR;
                OPC_SUB: command_out = CMD_SUB;
                OPC_ADD: command_out = CMD_ADD;
                OPC_ADC: command_out = CMD_ADC;
                OPC_SBC: command_out = CMD_SBC;
                OPC_ORR: command_out = CMD_ORR;
                OPC_TST: begin
                    command_out    = CMD_AND;
                    wb_en_out      = 1'b0;
                    dest_is_pc_out = 1'b0;
                    set_flags_out  = 1'b1;
                end
                OPC_CMP: begin
                    command_out    = CMD_SUB;
                    wb_en_out      = 1'b0;
                    dest_is_pc_out = 1'b0;
                    set_flags_out  = 1'b1;
                end
                OPC_MOV: begin
                    command_out  = CMD_MOV;
                    has_src1_out = 1'b0;
                end
                OPC_MVN: begin
                    command_out  = CMD_MVN;
                    has_src1_out = 1'b0;
                end
                default: begin
                    command_out    = CMD_NOP;
                    wb_en_out      = 1'b0;
                    dest_is_pc_out = 1'b0;
                    set_flags_out  = 1'b0;
                    has_src1_out   = 1'b0;
                    has_src2_out   = 1'b0;
                    immediate_out  = 1'b0;
                end
            endcase
        end else if (ldst_form_ok) begin
            memory_out   = 1'b1;
            command_out  = bit_u ? CMD_ADD : CMD_SUB;
            is_load_out  = bit_l;
            is_store_out = ~bit_l;
            wb_en_out    = bit_l;
            has_src1_out = 1'b1;
            has_src2_out = ~bit_l;
            src2_out     = field_rd;
        end else if ((mode == 2'b10) & bit_i) begin
            is_branch_out = 1'b1;
            link_out      = bit_p;
            wb_en_out     = bit_p;
            dest_out      = 4'd14;
        end
    end
endmodule
`default_nettype wire
