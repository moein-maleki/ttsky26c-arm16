"""Test programs for the arm16 cocotb suite: directed programs per instruction class, the re-encoded
lab regressions, and the random program generator. Every program writes a register before it reads it
(spec 10) and ends with a self-branch. r12 is reserved for the dump epilogue of the flash-fed tests."""

import random

DP_OPS = ["MOV", "MVN", "ADD", "ADC", "SUB", "SBC", "AND", "ORR", "EOR"]
TEST_OPS = ["CMP", "TST"]
CONDS = ["EQ", "NE", "CS", "CC", "MI", "PL", "VS", "VC", "HI", "LS", "GE", "LT", "GT", "LE", "AL"]
SHIFTS = ["LSL", "LSR", "ASR", "ROR"]
IMMEDIATES = [0, 1, 2, 3, 7, 8, 0x10, 0x7F, 0x80, 0xFF, 0x100, 0x3FC, 0x7F00, 0x8000, 0xFF00, 0xC000, 0x0FF0]

DIRECTED = {
    "dataproc_immediate": """
        MOV r0, #0x7F
        MOV r1, #0xFF00
        ADDS r2, r0, #1
        ADDS r3, r1, #0x100      ; carry out
        ADC r4, r3, #0
        ADCS r5, r1, #0xFF00     ; overflow and carry
        SUBS r6, r0, #0x80       ; borrow: C = 0, N = 1
        SBC r7, r0, #0
        SBCS r8, r1, #1
        ANDS r9, r1, #0xF0
        ORR r10, r0, #0x100
        EORS r11, r1, #0xFF00    ; Z = 1
        MVNS r13, #0
        MOVS r14, #0x8000        ; N = 1
        B .
    """,
    "dataproc_register": """
        MOV r0, #0x3FC
        MOV r1, #0x8000
        MOV r2, #5
        ADDS r3, r0, r1
        SUBS r4, r1, r0
        ADCS r5, r3, r4
        SBCS r6, r4, r3
        ANDS r7, r0, r1
        ORRS r8, r0, r1
        EORS r9, r0, r0
        MVN r10, r2
        MOV r11, r1
        CMP r0, r1
        MOV r13, r15
        CMP r0, r0
        TST r1, r1
        B .
    """,
    "shifts": """
        MOV r0, #0x8000
        ORR r0, r0, #1
        MOV r1, #0x3FC
        MOV r2, r0, LSL #1
        MOV r3, r0, LSL #15
        MOV r4, r0, LSL #16
        MOV r5, r0, LSR #1
        MOV r6, r0, LSR #15
        MOV r7, r0, LSR #17
        MOVS r8, r0, ASR #1
        MOV r9, r0, ASR #15
        MOV r10, r0, ASR #16
        MOV r11, r0, ASR #31
        MOV r13, r0, ROR #1
        MOV r14, r1, ROR #20
        ADD r1, r1, r0, LSL #2
        SUBS r2, r2, r0, ROR #4
        B .
    """,
    "branches": """
        MOV r0, #1
        MOV r1, r15              ; pc + 8 = 0x0C
        B skip1
        MOV r0, #2               ; flushed
        MOV r0, #3               ; flushed
    skip1:
        BL sub
        MOV r3, #7
        B back
    sub:
        MOV r2, #9
        MOV pc, lr
    fwd:
        MOV r5, #0x55
        B done
    back:
        MOV r4, #4
        B fwd
        MOV r4, #5
    done:
        ADD r6, r15, #4          ; pc + 12
        MOV r7, #0x48
        ADD pc, r7, #0           ; a data-processing write to r15: branch to the B . at 0x48
        B .
    """,
    "conditions": """
        MOV r0, #0
        MOV r1, #0
        MOV r2, #0
        MOV r3, #0
        MOV r4, #0
        MOV r5, #0
        MOV r6, #0
        MOV r7, #0
        MOV r8, #5
        CMP r8, #5               ; Z=1 C=1 N=0 V=0
        ADDEQ r0, r0, #1
        ADDNE r0, r0, #0x10
        ADDCS r1, r1, #1
        ADDCC r1, r1, #0x10
        ADDMI r2, r2, #1
        ADDPL r2, r2, #0x10
        ADDVS r3, r3, #1
        ADDVC r3, r3, #0x10
        ADDHI r4, r4, #1
        ADDLS r4, r4, #0x10
        ADDGE r5, r5, #1
        ADDLT r5, r5, #0x10
        ADDGT r6, r6, #1
        ADDLE r6, r6, #0x10
        ADDAL r7, r7, #1
        CMP r8, #6               ; N=1 C=0
        ADDMI r2, r2, #0x100
        ADDCC r1, r1, #0x100
        ADDLT r5, r5, #0x100
        ADDLE r6, r6, #0x100
        ADDHI r4, r4, #0x100
        MOV r9, #0x7F00
        ADDS r9, r9, #0x100      ; V=1 N=1
        ADDVS r3, r3, #0x100
        ADDGE r5, r5, #0x1000    ; N == V
        ADDGT r6, r6, #0x1000
        .word 0xF3A00099         ; MOV r0, #0x99 with condition 1111: never executes
        B .
    """,
    "unsupported_nop": """
        MOV r0, #1
        MOV r1, #2
        MOV r2, #3
        .word 0xE0610002         ; RSB r0, r1, r2
        .word 0xE0E10002         ; RSC r0, r1, r2
        .word 0xE1310002         ; TEQ r1, r2
        .word 0xE1710002         ; CMN r1, r2
        .word 0xE1C10002         ; BIC r1, r1, r2
        .word 0xE1A00112         ; MOV r0, r2, LSL r1 (register shift)
        .word 0xE0000291         ; MUL r0, r1, r2
        .word 0xE8BD0003         ; LDM
        .word 0xEF000000         ; SWI
        .word 0xE591F000         ; LDR pc, [r1]
        .word 0xE581F000         ; STR pc, [r1]
        .word 0xE4910004         ; LDR r0, [r1], #4 (post-index)
        .word 0xE5D10000         ; LDRB r0, [r1]
        .word 0xE10F1000         ; MRS r1, CPSR (TST opcode with S = 0): must not touch the flags
        .word 0xE129F001         ; MSR CPSR_fc, r1 (CMP opcode with S = 0)
        MOV r3, #4
        B .
    """,
    "peripherals": """
        MOV r0, #0xFF00
        MOV r1, #0x1200
        ORR r1, r1, #0x34
        STR r1, [r0, #0]         ; VGA_VAL
        LDR r2, [r0, #0]
        LDR r3, [r0, #2]         ; SW
        MOV r4, #0x2A
        STR r4, [r0, #0x10]      ; VGA_FG
        MOV r5, #0x15
        STR r5, [r0, #0x12]      ; VGA_BG
        LDR r6, [r0, #0x10]
        LDR r7, [r0, #0x12]
        LDR r8, [r0, #0x20]      ; unmapped: 0
        STR r1, [r0, #0x20]      ; unmapped: nothing
        MOV r9, #0xD0
        STR r9, [r0, #8]         ; UART_DIV
        LDR r10, [r0, #8]
        LDR r11, [r0, #0xC]      ; METER (some value; not compared)
        B .
    """,
    "regression_load_use": """
        MOV r2, #0xFF00
        MOV r5, #0x77
        STR r5, [r2, #0]
        MOV r1, #0x11            ; the stale value a missing stall would consume
        LDR r1, [r2, #0]         ; load: 0x77
        ADD r3, r1, #1           ; load-use: must see 0x77 -> 0x78, not 0x12
        LDR r4, [r2, #0]
        MOV r5, #9               ; independent
        ADD r6, r4, r4           ; a load two instructions back
        B .
    """,
    "regression_branch_beats_stall": """
        MOV r0, #1
        MOV r2, #0xFF00
        STR r0, [r2, #0]
        CMP r0, #1
        LDR r1, [r2, #0]
        BEQ target               ; taken branch right after a load
        ADD r1, r1, #0x10        ; must not execute
        ADD r1, r1, #0x20
    target:
        ADD r3, r1, #1           ; sees the loaded 1 -> 2
        B .
    """,
    "regression_flags_untouched": """
        MOV r0, #5
        MOV r2, #0xFF00
        CMP r0, #5               ; Z = 1
        LDR r1, [r2, #2]         ; L bit set: must not touch the flags
        ADDEQ r3, r0, #1         ; executes only if Z still 1
        CMP r0, #6               ; Z = 0, N = 1
        .word 0xEA100000         ; B .+8 with bit 20 set: never updates flags
        MOV r4, #0               ; skipped by the branch
        ADDNE r5, r0, #2         ; N = 1, Z = 0 preserved
        ADDS r6, r0, #0          ; S bit: N = 0
        B .
    """,
    "regression_mov_keeps_carry": """
        MOV r0, #0xFF00
        ADDS r1, r0, #0x100      ; C = 1
        MOV r2, #3               ; must keep C
        ORR r3, r2, #4
        ADC r4, r2, #0           ; 4 with C = 1
        MOVS r5, #0              ; keeps C, sets Z
        ADC r6, r2, #0           ; still 4
        B .
    """,
    "regression_ls_condition": """
        MOV r0, #1
        MOV r1, #0
        MOV r2, #0
        MOV r3, #0
        MOV r4, #0
        CMP r0, #2               ; C=0 Z=0 -> LS true
        ADDLS r1, r1, #1
        CMP r0, #1               ; C=1 Z=1 -> LS true
        ADDLS r2, r2, #1
        MOV r5, #2
        CMP r5, #1               ; C=1 Z=0 -> LS false
        ADDLS r3, r3, #1
        MOV r6, #0x8000
        CMP r6, #0x8000          ; C=1 Z=1
        ADDLS r4, r4, #1
        B .
    """,
    "bubble_never_writes": """
        MOV r0, #7
        MOV r1, #0
        CMP r0, r0               ; Z = 1: an ANDEQ r0,r0,r0 bubble would now write r0
        B skip
        MOV r0, #1
        MOV r0, #2
    skip:
        ADD r1, r1, #1
        B .
    """,
    "dependent_chain": """
        MOV r0, #0
        ADD r1, r0, #1
        ADD r2, r1, #1
        ADD r3, r2, #1
        ADD r4, r3, #1
        ADD r5, r4, #1
        ADD r6, r5, #1
        ADD r7, r6, #1
        ADD r8, r7, #1
        ADD r9, r8, #1
        ADD r10, r9, #1
        ADD r11, r10, #1
        ADD r13, r11, #1
        ADD r14, r13, #1
        B .
    """,
    "counted_loop": """
        MOV r0, #12
        MOV r1, #0
        MOV r2, #0xFF00
    loop:
        ADD r1, r1, r0
        STR r1, [r2, #0]
        SUBS r0, r0, #1
        BNE loop
        LDR r3, [r2, #0]
        B .
    """,
}


def random_program(seed, length=30, loop=False, psram=False):
    """A random straight-line program (or one with a counted loop) in the subset: peripheral memory
    accesses (and PSRAM accesses when psram=True), forward conditional branches, registers written before
    read. r12 is the peripheral base and is reserved."""
    rng = random.Random(seed)
    regs = [r for r in range(15) if r != 12]
    lines = []
    live = []
    for r in rng.sample(regs, 8):
        lines.append("MOV r%d, #0x%X" % (r, rng.choice(IMMEDIATES)))
        live.append(r)
    lines.append("MOV r12, #0xFF00")
    if psram:
        lines.append("MOV r11, #0x8100")
        if 11 not in live:
            live.append(11)
    label = 0
    count = 0
    while count < length:
        kind = rng.random()
        s = "S" if rng.random() < 0.4 else ""
        cond = rng.choice(CONDS) if rng.random() < 0.3 else "AL"
        if kind < 0.45:
            op = rng.choice(DP_OPS)
            rd = rng.choice([r for r in regs if not (psram and r == 11)])
            rn = rng.choice(live)
            form = rng.random()
            if form < 0.45:
                op2 = "#0x%X" % rng.choice(IMMEDIATES)
            elif form < 0.7:
                op2 = "r%d" % rng.choice(live + [15])
            else:
                op2 = "r%d, %s #%d" % (rng.choice(live), rng.choice(SHIFTS), rng.randint(1, 31))
            if op in ("MOV", "MVN"):
                lines.append("%s%s%s r%d, %s" % (op, cond, s, rd, op2))
            else:
                lines.append("%s%s%s r%d, r%d, %s" % (op, cond, s, rd, rn, op2))
            if cond == "AL" and rd not in live:
                live.append(rd)
        elif kind < 0.6:
            op = rng.choice(TEST_OPS)
            op2 = "#0x%X" % rng.choice(IMMEDIATES) if rng.random() < 0.5 else "r%d" % rng.choice(live)
            lines.append("%s%s r%d, %s" % (op, cond, rng.choice(live), op2))
        elif kind < 0.72:
            if psram and rng.random() < 0.7:
                lines.append("STR%s r%d, [r11, #%d]" % (cond, rng.choice([r for r in live if r != 11]), rng.choice([0, 2, 4, 6, 8])))
            else:
                lines.append("STR%s r%d, [r12, #0]" % (cond, rng.choice(live)))
        elif kind < 0.82:
            rd = rng.choice([r for r in regs if r != 11])
            if psram and rng.random() < 0.7:
                lines.append("LDR%s r%d, [r11, #%d]" % (cond, rd, rng.choice([0, 2, 4, 6, 8])))
            else:
                lines.append("LDR%s r%d, [r12, #%d]" % (cond, rd, rng.choice([0, 2, 0x10, 0x12])))
            if cond == "AL" and rd not in live:
                live.append(rd)
        elif kind < 0.9:
            rd = rng.choice(regs)
            lines.append("MOV r%d, r15" % rd)
            if rd not in live:
                live.append(rd)
        else:
            # forward conditional branch over one to three instructions, which stay in the count
            skip = rng.randint(1, 3)
            label += 1
            lines.append("B%s L%d" % (rng.choice(CONDS), label))
            for _ in range(skip):
                rd = rng.choice(live)
                lines.append("ADD r%d, r%d, #1" % (rd, rd))
                count += 1
            lines.append("L%d:" % label)
        count += 1
    if loop:
        lines.append("MOV r13, #%d" % rng.randint(2, 6))
        lines.append("MOV r14, #0")
        lines.append("LOOPTOP:")
        lines.append("ADD r14, r14, r13")
        lines.append("STR r14, [r12, #0]")
        lines.append("SUBS r13, r13, #1")
        lines.append("BNE LOOPTOP")
    lines.append("B .")
    return "\n".join(lines)
