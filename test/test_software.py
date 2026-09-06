"""pytest: encoder, image loading and golden-model semantics (sprint plan, task 1).

Run: cd test && python3 -m pytest test_software.py -q"""

import os
import shutil
import subprocess
import tempfile

import pytest

import arm16_asm as asm
from arm16_asm import AsmError, assemble, build_flash_image, decode, encode, epilogue
from arm16_model import Arm16Model, condition_met, shift_operand

KNOWN = [
    ("MOV", "r0, #20", 0xE3A00014),
    ("ADDS", "r1, r2, r3", 0xE0921003),
    ("SUBNE", "r4, r5, #1", 0x12454001),
    ("LDR", "r0, [r1, #4]", 0xE5910004),
    ("STR", "r0, [r1, #-4]", 0xE5010004),
    ("B", ".+8", 0xEA000000),
    ("BL", "0x100", 0xEB00003E),
    ("MOV", "pc, lr", 0xE1A0F00E),
    ("MOV", "r1, #0xFF00", 0xE3A01CFF),
    ("MOV", "r2, r3, LSL #4", 0xE1A02203),
    ("CMP", "r0, #0", 0xE3500000),
    ("TST", "r1, r2", 0xE1110002),
    ("MVN", "r3, #0", 0xE3E03000),
    ("ADC", "r0, r0, #0", 0xE2A00000),
    ("SBC", "r1, r1, r2, LSR #3", 0xE0C111A2),
    ("ORREQ", "r0, r0, #8", 0x03800008),
    ("ANDS", "r5, r6, r7, ASR #1", 0xE01650C7),
    ("EOR", "r1, r1, r1, ROR #15", 0xE02117E1),
    ("B", ".", 0xEAFFFFFE),
    ("BLS", ".", 0x9AFFFFFE),
    ("BLLS", ".", 0x9BFFFFFE),
]


@pytest.mark.parametrize("mnemonic,operands,word", KNOWN)
def test_encode_known_words(mnemonic, operands, word):
    assert encode(mnemonic, operands) == word


def test_suffix_orders_agree():
    assert encode("ADDNES", "r1, r2, r3") == encode("ADDSNE", "r1, r2, r3")
    assert encode("ADD", "r1, r2, r3", cond="NE") == encode("ADDNE", "r1, r2, r3")


@pytest.mark.parametrize("mnemonic,operands", [
    ("MOV", "r0, r1, LSL r2"),          # register-specified shift
    ("LDR", "r0, [r1], #4"),            # post-index
    ("LDR", "r0, [r1, #4]!"),           # writeback
    ("LDRB", "r0, [r1]"),               # byte access
    ("MOV", "r0, r1, LSR #0"),          # LSR #32 encoding
    ("MOV", "r0, r1, LSR #32"),
    ("MOV", "r0, r1, ROR #0"),          # RRX encoding
    ("MOV", "r0, r1, RRX"),
    ("RSB", "r0, r1, r2"),              # unsupported opcode
    ("BIC", "r0, r1, #1"),
    ("MOV", "r0, #0xC003"),             # not a rotated 8-bit immediate
    ("LDR", "pc, [r0]"),                # LDR to r15
    ("MUL", "r0, r1, r2"),
])
def test_encode_rejects(mnemonic, operands):
    with pytest.raises(AsmError):
        encode(mnemonic, operands)


def test_decode_round_trip():
    for mnemonic, operands, word in KNOWN:
        d = decode(word)
        assert d["valid"]
        base = mnemonic.rstrip("S") if mnemonic not in ("BLS", "BLLS") else "B"
        if mnemonic in ("B", "BLS"):
            assert d["cls"] == "branch" and not d["link"]
        elif mnemonic in ("BL", "BLLS"):
            assert d["cls"] == "branch" and d["link"]
        elif mnemonic in ("LDR", "STR"):
            assert d["cls"] == "ldst" and d["name"] == mnemonic
        else:
            assert d["cls"] == "dp", mnemonic
            assert d["name"] == base[:3] or d["name"] == mnemonic[:3]
    # unsupported words decode to nop
    assert decode(0xE0610002)["cls"] == "nop"          # RSB
    assert decode(0xE1A00112)["cls"] == "nop"          # MOV r0, r2, LSL r1 (bit 4)
    assert decode(0xE4910004)["cls"] == "nop"          # post-indexed LDR
    assert decode(0xE8BD8000)["cls"] == "nop"          # LDM
    assert decode(0xEF000000)["cls"] == "nop"          # SWI (mode 11)
    assert decode(0xE591F000)["cls"] == "nop"          # LDR pc
    assert not decode(0xF0000000)["valid"]             # the bubble marker
    assert decode(0x00000000)["cls"] == "dp" and decode(0x00000000)["cond"] == 0   # ANDEQ: the old bubble defect


def test_immediate_ring_property():
    """Every 16-bit constant the 32-bit encoding produces has the same value in the 16-bit ring."""
    for value in range(0x10000):
        try:
            rot, imm8 = asm.encode_immediate(value)
        except AsmError:
            continue
        assert asm.rotate_right_16(imm8, 2 * rot) == value


def run_words(words, **kw):
    m = Arm16Model(build_flash_image(words), **kw)
    for _ in range(len(words)):
        m.step()
    return m


def test_flags_definition():
    def dp(mnemonic, ops, **regs):
        m = Arm16Model(build_flash_image(assemble("MOV r0, #0\n" + mnemonic + " " + ops)))
        for r, v in regs.items():
            m.regs[int(r[1:])] = v
        m.step(); m.step()
        return m
    m = dp("ADDS", "r0, r1, #1", r1=0xFFFF); assert (m.regs[0], m.n, m.z, m.c, m.v) == (0, False, True, True, False)
    m = dp("SUBS", "r0, r1, #1", r1=0); assert (m.regs[0], m.n, m.z, m.c, m.v) == (0xFFFF, True, False, False, False)
    m = dp("ADDS", "r0, r1, #1", r1=0x7FFF); assert (m.regs[0], m.n, m.v) == (0x8000, True, True)
    m = dp("SUBS", "r0, r1, #1", r1=0x8000); assert (m.regs[0], m.v, m.c) == (0x7FFF, True, True)
    m = dp("CMP", "r1, #5", r1=5); assert (m.z, m.c, m.n, m.v) == (True, True, False, False)
    m = dp("CMP", "r1, #6", r1=5); assert (m.z, m.c, m.n) == (False, False, True)
    m = dp("SUBS", "r0, r1, r2", r1=3, r2=5); assert (m.regs[0], m.c, m.n, m.v) == (0xFFFE, False, True, False)
    m = dp("SUBS", "r0, r1, r2", r1=5, r2=3); assert (m.regs[0], m.c) == (2, True)
    # ADC and SBC use C in
    m = Arm16Model(build_flash_image(assemble("MOV r0, #0\nADDS r0, r1, #1\nADC r2, r3, #0\nSUBS r0, r4, #1\nSBC r5, r6, #0")))
    m.regs[1] = 0xFFFF; m.regs[3] = 10; m.regs[4] = 0; m.regs[6] = 10
    for _ in range(5):
        m.step()
    assert m.regs[2] == 11        # ADC with C = 1
    assert m.regs[5] == 9         # SBC with C = 0 subtracts one more
    # MOVS leaves C and V; TST sets N and Z only
    m = Arm16Model(build_flash_image(assemble("MOV r0, #0\nADDS r0, r1, #1\nMOVS r2, #0\nTST r3, #1")))
    m.regs[1] = 0x7FFF; m.regs[3] = 0x8001
    for _ in range(4):
        m.step()
    assert (m.c, m.v) == (False, True) and m.z is False and m.n is False   # TST 0x8001 & 1 = 1: N0 Z0; C V from ADDS
    m = Arm16Model(build_flash_image(assemble("MOV r0, #0\nADDS r0, r1, #1\nMOVS r2, #0")))
    m.regs[1] = 0xFFFF
    for _ in range(3):
        m.step()
    assert (m.z, m.c, m.v) == (True, True, False)     # MOVS #0 sets Z, keeps C from the ADDS


def test_shifts_definition():
    assert shift_operand(0x8001, 0, 1) == 0x0002
    assert shift_operand(0x8001, 0, 16) == 0
    assert shift_operand(0x8001, 1, 1) == 0x4000
    assert shift_operand(0x8001, 1, 20) == 0
    assert shift_operand(0x8001, 2, 1) == 0xC000
    assert shift_operand(0x8001, 2, 31) == 0xFFFF
    assert shift_operand(0x0001, 2, 31) == 0
    assert shift_operand(0x8001, 3, 1) == 0xC000
    assert shift_operand(0x1234, 3, 20) == shift_operand(0x1234, 3, 4)


def test_conditions_table():
    n, z, c, v = True, False, True, False
    assert condition_met(4, n, z, c, v) and condition_met(2, n, z, c, v) and condition_met(8, n, z, c, v)
    assert not condition_met(9, n, z, c, v) and not condition_met(15, n, z, c, v) and condition_met(14, n, z, c, v)
    assert condition_met(11, True, False, False, False) and condition_met(13, True, False, False, False)


def test_image_loading():
    words = assemble("MOV r0, #1\nMOV r1, #2\nB .")
    img = build_flash_image(words)
    assert len(img) == 32768
    for i, w in enumerate(words):
        assert img[4 * i:4 * i + 4] == w.to_bytes(4, "little")
    assert img[12:16] == b"\xff\xff\xff\xff"
    m = Arm16Model(img)
    m.step()
    assert m.regs[0] == 1 and m.pc == 4
    # a program at another origin runs when the pc is set there
    words2 = assemble("MOV r5, #9\nB .", origin=0x100)
    img2 = build_flash_image(words2, origin=0x100)
    m2 = Arm16Model(img2)
    m2.pc = 0x100
    m2.step()
    assert m2.regs[5] == 9 and m2.pc == 0x104
    # the flash model view: byte address equals CPU address (a shifted address would break this)
    assert int.from_bytes(img2[0x100:0x104], "little") == words2[0]


def test_model_semantics():
    src = """
        MOV r0, r15          ; r0 = 0 + 8
        BL sub               ; r14 = 8
        MOV r3, #3
        B done
    sub:
        MOV r1, #7
        MOV pc, lr
    done:
        MOV r4, #0x80
        STR r4, [r4, #0]     ; store to 0x0080 (flash range): nothing happens
        MOV r5, #0x8000
        STR r4, [r5, #2]     ; PSRAM 0x8002 = 0x80
        LDR r6, [r5, #2]
        MOV r7, #0xFF00
        STR r6, [r7, #0]     ; VGA_VAL = 0x80
        LDR r8, [r7, #2]     ; SW
        .word 0xE0699009     ; RSB r9, r9, r9: unsupported, NOP, still retires
        B .
    """
    words = assemble(src)
    m = Arm16Model(build_flash_image(words), sw=0x5A)
    m.regs[9] = 0x1234
    n = m.run()
    assert m.regs[0] == 8
    assert m.regs[14] == 8 and m.regs[1] == 7 and m.regs[3] == 3
    assert m.regs[6] == 0x80 and m.psram[2:4] == b"\x80\x00"
    assert m.vga_val == 0x80 and m.regs[8] == 0x5A
    assert m.regs[9] == 0x1234
    assert m.bus_transactions == 2           # the PSRAM store and load; the flash store and peripherals count nothing
    assert m.retired == n
    assert m.pc == 4 * (len(words) - 1)
    # backward loop terminates by count
    loop = assemble("MOV r0, #5\nMOV r1, #0\nloop: ADD r1, r1, #2\nSUBS r0, r0, #1\nBNE loop\nB .")
    m = Arm16Model(build_flash_image(loop))
    m.run()
    assert m.regs[1] == 10 and m.z


def test_epilogue_layout():
    words = assemble("MOV r1, #1\n" + epilogue())
    m = Arm16Model(build_flash_image(words))
    m.regs[13] = 0x1313
    m.run()
    base = 0x9F00 - 0x8000
    layout = asm.EPILOGUE_LAYOUT
    dump = [int.from_bytes(m.psram[base + 2 * k: base + 2 * k + 2], "little") for k in range(16)]
    assert dump[1] == 1 and dump[12] == 0x1313
    assert dump[layout["done_slot"]] == layout["done_value"]
    assert dump[layout["flags_slot"]] == m.flags_word()


@pytest.mark.skipif(shutil.which("arm-none-eabi-as") is None, reason="binutils-arm-none-eabi not installed")
def test_cross_check_binutils():
    programs = [
        "MOV r0, #20\nADDS r1, r2, r3\nSUBNE r4, r5, #1\nLDR r0, [r1, #4]\nSTR r0, [r1, #-4]\nMOV pc, lr\nMOV r1, #0xFF00\nMOV r2, r3, LSL #4\nCMP r0, #0\nTST r1, r2\nMVN r3, #0",
        "loop: ADD r1, r1, #2\nSUBS r0, r0, #1\nBNE loop\nBL loop\nB .",
    ]
    for src in programs:
        ours = build_flash_image(assemble(src))[: 4 * len(src.splitlines())]
        with tempfile.TemporaryDirectory() as d:
            s = os.path.join(d, "p.s")
            open(s, "w").write(".arm\n.text\n" + src + "\n")
            subprocess.check_call(["arm-none-eabi-as", "-march=armv4", "-o", d + "/p.o", s])
            subprocess.check_call(["arm-none-eabi-objcopy", "-O", "binary", "-j", ".text", d + "/p.o", d + "/p.bin"])
            theirs = open(d + "/p.bin", "rb").read()
        assert ours == theirs


def test_shipped_demo_rom_matches_source():
    """src/demo_rom.v carries exactly the words of programs/demo_rom.s (plan decision D8)."""
    import re
    here = os.path.dirname(os.path.abspath(__file__))
    words = assemble(open(os.path.join(here, "programs", "demo_rom.s")).read())
    assert len(words) == 16
    rom = open(os.path.join(here, "..", "src", "demo_rom.v")).read()
    found = {int(m.group(1)): int(m.group(2), 16) for m in re.finditer(r"4'd(\d+)\s*:\s*word_out = 32'h([0-9A-Fa-f]{8})", rom)}
    assert [found[i] for i in range(16)] == words
    # the program's shape (spec 3.5): unused entries branch to themselves, no loads
    assert words[15] == 0xEAFFFFFE
    assert all(decode(w)["cls"] != "ldst" or decode(w)["name"] == "STR" for w in words)
