# 04_spec: decoder and datapath audit that fed the specification

> 2026-09-04. Read before writing RTL. File references are into
> `scratch_pad/2026-09-04_sep/02_arm16_fit_probe/rtl/`, the unverified probe.

## What the lab core decodes (control_unit.v, ID_stage.v)

- Condition [31:28]: all fourteen conditions plus AL; 0b1111 falls to the default and never executes.
- Mode [27:26]: 00 data processing, 01 load/store, 10 branch. Mode 11 decodes to NOP.
- Data processing opcodes decoded: MOV 1101, MVN 1111, ADD 0100, ADC 0101, SUB 0010, SBC 0110, AND 0000,
  ORR 1100, EOR 0001, CMP 1010, TST 1000. Not decoded, so NOP: RSB, RSC, TEQ, CMN, BIC.
- Operand 2: immediate (bit 25) as 8-bit value rotated by 2 x rot; otherwise Rm shifted by the 5-bit
  immediate in [11:7] with type [6:5]. Bit 4 (register-specified shift) is not decoded.
- Load/store: L bit [20] selects LDR (1) or STR (0). Bits P, U, B, W, I are not decoded. The offset
  `instr_offset_12` is sign-extended as if signed (val2_generator.v), so a standard-encoded negative offset
  (U = 0, positive magnitude) is added, not subtracted.
- Branch: `branch_immediate = $signed(instr[23:0])` truncated to 16 bits, and EXE computes
  `branch_address = branch_immediate + pc_plus_four` (EXE_stage.v). The offset is in bytes from PC + 4 and
  is not shifted. Standard ARM is words from PC + 8. The L bit [24] is not decoded, so BL acts as B.
- Register file (register_file.v): 15 entries, `[14:0]`; index 15 is out of range. r15 as a source is
  undefined. Writes with Rd = 15 go nowhere. Writes happen on the falling clock edge. There is no reset; an
  `initial` block sets entry i to i in simulation only.
- Status register writes on the falling edge, asynchronous reset.

## Defects found in this audit (beyond the five fixed on 2026-08-10)

| # | Where | What | Effect |
|---|---|---|---|
| 1 | alu.v N and V | `alu_result[31]`, `alu_in_1[31]`, `alu_in_2[31]` on 16-bit signals after the mechanical narrowing | N and V are constant; MI, PL, VS, VC, GE, LT, GT, LE are wrong |
| 2 | alu.v C | operands declared `signed`, so `{c, r} = a - b` sign-extends to 17 bits; c is the borrow, not NOT-borrow; on ADD, `0xFFFF + 1` gives c = 0 | C is inverted on SUB, SBC, CMP and wrong on some additions; CS, CC, HI, LS and ADC/SBC chains are wrong. Present in the original 32-bit lab ALU too (`arm-cache/alu.v`), so the lab's tests did not exercise it |
| 3 | alu.v ADC/SBC | `{31'b0, sr_bit_C_in}` width left over from 32 bits | harmless after truncation, clean it |
| 4 | val2_generator.v | `_32bit_immediate_base = {24'b0, immed_8}` into a 16-bit wire | harmless, clean it |
| 5 | EXE_stage.v branch | unshifted byte offset from PC + 4 | standard assembler output does not run |
| 6 | val2_generator.v offset | U bit ignored | standard assembler output does not run for negative offsets |
| 7 | control_unit.v BL | L bit ignored | no subroutine calls |
| 8 | register_file.v r15 | not present | no PC-relative loads, no return |
| 9 | qspi_master.v | four defects, see `03_memory_options/REPORT.md` | does not talk to the Pmod |

Defect 2 was confirmed by simulation of the probe ALU (`evidence/alu_flag_check.log`).

## Decisions these findings produced (spec section 17)

Standard ARM encoding for the subset; flags rewritten from the ARM definition; a golden model written from
the ARM definition, not from the RTL; the general registers left without reset, as ARM does; the lab's five
regressions carried but re-encoded where branch or offset encodings changed.

## Immediate rotation in a 16-bit ring

For any 16-bit constant that a standard assembler encodes as `imm8 ror (2 x rot)` in 32 bits, the same
`imm8` and `rot` rotated in a 16-bit ring give the same value. Proof sketch: a value that fits 16 bits is
either `imm8 << k` for k in 0..8 (rot = 16 - k/2 in 32 bits, and the 16-bit rotation `ror (32 - k) mod 16
= ror (16 - k)` equals `<< k` when the value fits), or `imm8 ror (2 x rot)` with 2 x rot at most 8, which
is identical in both widths. So `arm-none-eabi-as` immediates are correct without change.
