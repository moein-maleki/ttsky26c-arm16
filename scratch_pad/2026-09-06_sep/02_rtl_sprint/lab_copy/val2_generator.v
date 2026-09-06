`define SHIFTTYPE_LSL       2'b00
`define SHIFTTYPE_LSR       2'b01
`define SHIFTTYPE_ASR       2'b10    
`define SHIFTTYPE_ROR       2'b11

module val2_generator(
    input signed    [31:0]  val_rm,
    input           [11:0]  instr_shifter_opperand,
    input                   instr_is_memory_access,
    input                   instr_is_immediate,
    
    output signed   [31:0]  val2
);

    wire        [31:0]  _32bit_immediate;
    wire        [63:0]  _32bit_immediate_rail;
    wire        [63:0]  _32bit_immediate_rail_shifted;
    wire        [31:0]  _32bit_immediate_base;

    wire        [31:0]  shift_immediate;
    wire        [63:0]  shift_immediate_rotate_rail;
    wire        [63:0]  shift_immediate_rotate_rail_shifted;
    wire        [31:0]  shift_immediate_rotate;
    wire        [31:0]  shift_immediate_lsl;
    wire        [31:0]  shift_immediate_lsr;
    wire        [31:0]  shift_immediate_asr;

    wire        [31:0]  arithmatic_immediate;
    wire        [31:0]  load_store_immediate;

    wire        [1:0]   instr_shift_type;
    wire        [4:0]   instr_shift_immediate;
    wire        [7:0]   instr_immed_8;
    wire        [3:0]   instr_rotate_imm;
    wire        [11:0]  instr_offset_12;

    assign instr_shift_type         = instr_shifter_opperand[6:5];
    assign instr_shift_immediate    = instr_shifter_opperand[11:7];
    assign instr_offset_12          = instr_shifter_opperand[11:0];
    assign instr_immed_8            = instr_shifter_opperand[7:0];
    assign instr_rotate_imm         = instr_shifter_opperand[11:8];

    // immediates 
    assign load_store_immediate     = $signed(instr_offset_12);
    assign arithmatic_immediate     =
        (instr_is_immediate)        ? (_32bit_immediate) :
        (~instr_is_immediate)       ? (shift_immediate) : (32'bx);

    assign _32bit_immediate_base    = {24'b0, instr_immed_8};
    assign _32bit_immediate_rail    = {_32bit_immediate_base, _32bit_immediate_base};
    assign _32bit_immediate_rail_shifted    = (_32bit_immediate_rail) >> ({1'b0, instr_rotate_imm} << 1);
    assign _32bit_immediate         = _32bit_immediate_rail_shifted[31:0];

    assign shift_immediate_rotate_rail = {val_rm, val_rm};
    assign shift_immediate_rotate_rail_shifted = (shift_immediate_rotate_rail) >> (instr_shift_immediate);
    assign shift_immediate_rotate   = shift_immediate_rotate_rail_shifted[31:0];
    assign shift_immediate_lsl      = (val_rm) << (instr_shift_immediate);
    assign shift_immediate_lsr      = (val_rm) >> (instr_shift_immediate);
    assign shift_immediate_asr      = (val_rm) >>> (instr_shift_immediate);

    assign shift_immediate          =
        (instr_shift_type == `SHIFTTYPE_LSL) ? (shift_immediate_lsl) :
        (instr_shift_type == `SHIFTTYPE_LSR) ? (shift_immediate_lsr) :
        (instr_shift_type == `SHIFTTYPE_ASR) ? (shift_immediate_asr) :
        (instr_shift_type == `SHIFTTYPE_ROR) ? (shift_immediate_rotate) :
        32'bx;
    
    assign val2                     =
        (instr_is_memory_access)    ? (load_store_immediate) : (arithmatic_immediate);

endmodule