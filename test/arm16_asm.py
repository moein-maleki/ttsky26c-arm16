"""arm16 encoder, image builder and reference decoder for the instruction subset of docs/spec.md 3.1.

Software testbench, task 1 of the sprint plan. Every encoding is the standard 32-bit ARM encoding
(ARMv4), so the words this module produces are what arm-none-eabi-as produces for the same source.
Deviations that are decided for the chip (plan decisions D1, D2) are enforced here as rejections.
"""

import re

COND = {
    "EQ": 0, "NE": 1, "CS": 2, "HS": 2, "CC": 3, "LO": 3, "MI": 4, "PL": 5, "VS": 6, "VC": 7,
    "HI": 8, "LS": 9, "GE": 10, "LT": 11, "GT": 12, "LE": 13, "AL": 14,
}
COND_NAMES = {v: k for k, v in COND.items() if k not in ("HS", "LO")}

DP_OPCODE = {
    "AND": 0x0, "EOR": 0x1, "SUB": 0x2, "RSB": 0x3, "ADD": 0x4, "ADC": 0x5, "SBC": 0x6, "RSC": 0x7,
    "TST": 0x8, "TEQ": 0x9, "CMP": 0xA, "CMN": 0xB, "ORR": 0xC, "MOV": 0xD, "BIC": 0xE, "MVN": 0xF,
}
SUPPORTED_DP = {"MOV", "MVN", "ADD", "ADC", "SUB", "SBC", "AND", "ORR", "EOR", "CMP", "TST"}
TEST_OPS = {"TST", "TEQ", "CMP", "CMN"}
MOVE_OPS = {"MOV", "MVN"}
SHIFT_TYPE = {"LSL": 0, "LSR": 1, "ASR": 2, "ROR": 3}
REG_ALIAS = {"SP": 13, "LR": 14, "PC": 15, "IP": 12, "FP": 11}

MNEMONICS = sorted(SUPPORTED_DP | {"LDR", "STR", "B", "BL"}, key=len, reverse=True)


class AsmError(Exception):
    """Raised for any source outside the supported subset."""


# ----------------------------------------------------------------------------------------------
# operand parsing


def parse_reg(text):
    t = text.strip().upper()
    if t in REG_ALIAS:
        return REG_ALIAS[t]
    m = re.fullmatch(r"R(\d+)", t)
    if not m or int(m.group(1)) > 15:
        raise AsmError("bad register: %r" % text)
    return int(m.group(1))


def parse_int(text):
    t = text.strip().lower().replace("#", "")
    neg = t.startswith("-")
    if neg:
        t = t[1:]
    if t.startswith("0x"):
        v = int(t, 16)
    elif t.startswith("0b"):
        v = int(t, 2)
    elif re.fullmatch(r"\d+", t):
        v = int(t, 10)
    else:
        raise AsmError("bad number: %r" % text)
    return -v if neg else v


def encode_immediate(value):
    """Return (rot, imm8) such that imm8 ROR (2 * rot) == value in the 32-bit definition.

    The value must fit 16 bits (negative values are taken as 16-bit two's complement). Because the
    32-bit result fits 16 bits, the 16-bit ring rotation of the chip gives the same value (spec 3.1)."""
    if not -32768 <= value <= 0xFFFF:
        raise AsmError("immediate %d does not fit 16 bits" % value)
    value &= 0xFFFF
    for rot in range(16):
        s = 2 * rot
        # candidate: rotate the value LEFT by s in 32 bits and see if it fits 8 bits
        left = ((value << s) | (value >> (32 - s))) & 0xFFFFFFFF if s else value
        if left <= 0xFF:
            return rot, left
    raise AsmError("immediate 0x%04X is not an 8-bit value rotated by an even amount" % value)


def rotate_right_16(value, amount):
    amount %= 16
    value &= 0xFFFF
    return ((value >> amount) | (value << (16 - amount))) & 0xFFFF if amount else value


def _parse_operand2(text):
    """Return the 12-bit operand-2 field and the I bit for a data-processing operand."""
    t = text.strip()
    if t.startswith("#"):
        rot, imm8 = encode_immediate(parse_int(t))
        return 1, (rot << 8) | imm8
    parts = [p.strip() for p in t.split(",")]
    rm = parse_reg(parts[0])
    if len(parts) == 1:
        return 0, rm
    if len(parts) != 2:
        raise AsmError("bad operand 2: %r" % text)
    m = re.fullmatch(r"(LSL|LSR|ASR|ROR|RRX)\s*(#.*)?", parts[1].upper())
    if not m:
        raise AsmError("bad shift: %r" % parts[1])
    kind = m.group(1)
    if kind == "RRX":
        raise AsmError("RRX is not supported (plan decision D1)")
    if not m.group(2):
        raise AsmError("register-specified shifts are not supported (spec 4)")
    amount = parse_int(m.group(2))
    if kind in ("LSR", "ASR") and amount == 32:
        raise AsmError("%s #32 is not supported (plan decision D1)" % kind)
    if not 0 <= amount <= 31:
        raise AsmError("shift amount out of range: %d" % amount)
    if kind in ("LSR", "ASR", "ROR") and amount == 0:
        raise AsmError("%s #0 is a special ARM encoding and is not supported (plan decision D1)" % kind)
    return 0, (amount << 7) | (SHIFT_TYPE[kind] << 5) | rm


def _split_mnemonic(word):
    """Return (base, cond, s_bit) from a mnemonic such as ADDNES, ADDSNE, BLEQ, BLS, MOVS."""
    w = word.upper()
    for base in MNEMONICS:
        if not w.startswith(base):
            continue
        rest = w[len(base):]
        if base == "B" and rest.startswith("L") and len(rest) >= 3 and rest[1:3] in COND:
            continue  # this is BL + cond, matched by the BL entry
        s_bit = 0
        cond = "AL"
        if rest == "":
            pass
        elif rest == "S" and base in SUPPORTED_DP:
            s_bit = 1
        elif rest in COND:
            cond = rest
        elif len(rest) == 3 and base in SUPPORTED_DP and rest[0] == "S" and rest[1:] in COND:
            s_bit, cond = 1, rest[1:]
        elif len(rest) == 3 and base in SUPPORTED_DP and rest[2] == "S" and rest[:2] in COND:
            s_bit, cond = 1, rest[:2]
        else:
            continue
        if base in TEST_OPS:
            s_bit = 1
        return base, cond, s_bit
    raise AsmError("unknown mnemonic: %r" % word)


# ----------------------------------------------------------------------------------------------
# encoding


def _resolve_target(text, pc, labels):
    t = text.strip()
    if t == ".":
        return pc
    m = re.fullmatch(r"\.\s*([+-])\s*(.+)", t)
    if m:
        off = parse_int(m.group(2))
        return pc + (off if m.group(1) == "+" else -off)
    if labels is not None and t in labels:
        return labels[t]
    try:
        return parse_int(t)
    except AsmError:
        raise AsmError("unknown label: %r" % t)


def encode(mnemonic, operands, cond=None, pc=0, labels=None):
    """Encode one instruction and return its 32-bit word.

    `mnemonic` may carry the condition and the S suffix (ADDNES or ADDSNE); `cond` overrides it."""
    base, mcond, s_bit = _split_mnemonic(mnemonic)
    if cond is not None:
        mcond = cond.upper()
    if mcond not in COND:
        raise AsmError("bad condition: %r" % mcond)
    c = COND[mcond] << 28
    ops = [o.strip() for o in _split_operands(operands)]

    if base in SUPPORTED_DP:
        opc = DP_OPCODE[base]
        if base in MOVE_OPS:
            if len(ops) < 2:
                raise AsmError("%s needs Rd and an operand" % base)
            rd, rn = parse_reg(ops[0]), 0
            i_bit, op2 = _parse_operand2(", ".join(ops[1:]))
        elif base in TEST_OPS:
            if len(ops) < 2:
                raise AsmError("%s needs Rn and an operand" % base)
            rd, rn = 0, parse_reg(ops[0])
            i_bit, op2 = _parse_operand2(", ".join(ops[1:]))
        else:
            if len(ops) < 3:
                raise AsmError("%s needs Rd, Rn and an operand" % base)
            rd, rn = parse_reg(ops[0]), parse_reg(ops[1])
            i_bit, op2 = _parse_operand2(", ".join(ops[2:]))
        return c | (i_bit << 25) | (opc << 21) | (s_bit << 20) | (rn << 16) | (rd << 12) | op2

    if base in ("LDR", "STR"):
        if len(ops) < 2:
            raise AsmError("%s needs Rd and [Rn, #offset]" % base)
        rd = parse_reg(ops[0])
        mem = ", ".join(ops[1:]).strip()
        m = re.fullmatch(r"\[\s*([A-Za-z0-9]+)\s*(?:,\s*(#[^\]]+))?\s*\](!?)(.*)", mem)
        if not m:
            raise AsmError("bad address operand: %r" % mem)
        if m.group(3) or m.group(4).strip():
            raise AsmError("writeback and post-indexing are not supported (spec 4)")
        rn = parse_reg(m.group(1))
        off = parse_int(m.group(2)) if m.group(2) else 0
        u_bit = 1 if off >= 0 else 0
        off = abs(off)
        if off > 4095:
            raise AsmError("offset out of range: %d" % off)
        if rd == 15:
            raise AsmError("%s of r15 is not supported (spec 4, plan D2)" % base)
        l_bit = 1 if base == "LDR" else 0
        return c | (0b01 << 26) | (1 << 24) | (u_bit << 23) | (l_bit << 20) | (rn << 16) | (rd << 12) | off

    if base in ("B", "BL"):
        if len(ops) != 1:
            raise AsmError("%s needs one target" % base)
        target = _resolve_target(ops[0], pc, labels)
        delta = target - (pc + 8)
        if delta % 4:
            raise AsmError("branch target %r is not word aligned" % ops[0])
        imm24 = (delta >> 2) & 0xFFFFFF
        return c | (0b101 << 25) | ((1 if base == "BL" else 0) << 24) | imm24

    raise AsmError("unsupported mnemonic: %r" % mnemonic)


def _split_operands(text):
    """Split on commas that are not inside brackets."""
    out, depth, cur = [], 0, ""
    for ch in text:
        if ch == "[":
            depth += 1
        elif ch == "]":
            depth -= 1
        if ch == "," and depth == 0:
            out.append(cur)
            cur = ""
        else:
            cur += ch
    if cur.strip():
        out.append(cur)
    return out


def _strip_comment(line):
    for marker in (";", "@", "//"):
        idx = line.find(marker)
        if idx >= 0:
            line = line[:idx]
    return line.strip()


def assemble(source, origin=0):
    """Assemble a program text into a list of 32-bit words, labels resolved. Word i sits at
    origin + 4 * i. Supports `label:`, `.org`, `.word`, comments with ; @ or //."""
    lines = [_strip_comment(l) for l in source.splitlines()]
    # pass 1: labels
    labels, pc, items = {}, origin, []
    for raw in lines:
        line = raw
        while line:
            m = re.match(r"([A-Za-z_.][A-Za-z0-9_]*):\s*", line)
            if not m:
                break
            labels[m.group(1)] = pc
            line = line[m.end():]
        if not line:
            continue
        if line.startswith(".org"):
            new_pc = parse_int(line.split()[1])
            if new_pc < pc or (new_pc - origin) % 4:
                raise AsmError(".org must move forward by whole words")
            while pc < new_pc:
                items.append((pc, "B", "."))   # padding words branch to themselves
                pc += 4
            continue
        if line.startswith(".word"):
            items.append((pc, ".word", line[5:].strip()))
            pc += 4
            continue
        parts = line.split(None, 1)
        items.append((pc, parts[0], parts[1] if len(parts) > 1 else ""))
        pc += 4
    # pass 2: encode
    words = []
    for addr, mnemonic, operands in items:
        if mnemonic == ".word":
            words.append(parse_int(operands) & 0xFFFFFFFF)
        else:
            words.append(encode(mnemonic, operands, pc=addr, labels=labels))
    return words


def build_flash_image(words, size=32768, origin=0):
    """Return a little-endian byte image with word i at byte offset origin + 4 * i."""
    img = bytearray(b"\xff" * size)
    for i, w in enumerate(words):
        off = origin + 4 * i
        if off + 4 > size:
            raise AsmError("program does not fit the image")
        img[off:off + 4] = (w & 0xFFFFFFFF).to_bytes(4, "little")
    return bytes(img)


def epilogue(base=0x9F00):
    """The dump epilogue for flash-fed tests: stores r0 to r11, r13, r14, the flags and a done marker
    to PSRAM at `base`. r12 is the scratch base register and is not preserved."""
    lines = ["MOV r12, #0x%04X" % base]
    slot = 0
    for r in list(range(12)) + [13, 14]:
        lines.append("STR r%d, [r12, #%d]" % (r, 2 * slot))
        slot += 1
    flags_off, done_off = 2 * slot, 2 * slot + 2
    lines += [
        "MOV r0, #0",
        "ORRMI r0, r0, #8",
        "ORREQ r0, r0, #4",
        "ORRCS r0, r0, #2",
        "ORRVS r0, r0, #1",
        "STR r0, [r12, #%d]" % flags_off,
        "MOV r0, #0xCE",
        "STR r0, [r12, #%d]" % done_off,
        "B .",
    ]
    return "\n".join(lines)


EPILOGUE_LAYOUT = {"regs": list(range(12)) + [13, 14], "flags_slot": 14, "done_slot": 15, "done_value": 0xCE}


# ----------------------------------------------------------------------------------------------
# reference decoder


def sign_extend(value, bits):
    value &= (1 << bits) - 1
    return value - (1 << bits) if value & (1 << (bits - 1)) else value


def decode(word):
    """Reference decoder. Returns a dict with the class of the word and every field the model needs.

    cls: 'dp' (data processing), 'ldst', 'branch', 'nop' (unsupported: no write, no flags)."""
    word &= 0xFFFFFFFF
    d = {"word": word, "cond": word >> 28, "valid": (word >> 28) != 0xF}
    mode = (word >> 26) & 3
    if mode == 0:
        d["cls"] = "dp"
        d["i"] = (word >> 25) & 1
        d["opcode"] = (word >> 21) & 0xF
        d["s"] = (word >> 20) & 1
        d["rn"] = (word >> 16) & 0xF
        d["rd"] = (word >> 12) & 0xF
        d["op2"] = word & 0xFFF
        names = {v: k for k, v in DP_OPCODE.items()}
        d["name"] = names[d["opcode"]]
        if d["name"] not in SUPPORTED_DP:
            d["cls"] = "nop"
        if d["name"] in TEST_OPS and not d["s"]:
            d["cls"] = "nop"           # MRS, MSR and friends: TST/CMP opcodes with S = 0
        if d["i"]:
            d["rot"], d["imm8"] = (word >> 8) & 0xF, word & 0xFF
        else:
            d["shift_amount"] = (word >> 7) & 0x1F
            d["shift_type"] = (word >> 5) & 3
            d["rm"] = word & 0xF
            if (word >> 4) & 1:
                d["cls"] = "nop"       # register-specified shift
    elif mode == 1:
        d["cls"] = "ldst"
        d["i"] = (word >> 25) & 1
        d["p"], d["u"], d["b"], d["w"], d["l"] = [(word >> k) & 1 for k in (24, 23, 22, 21, 20)]
        d["rn"], d["rd"], d["imm12"] = (word >> 16) & 0xF, (word >> 12) & 0xF, word & 0xFFF
        d["name"] = "LDR" if d["l"] else "STR"
        if d["i"] or not d["p"] or d["b"] or d["w"]:
            d["cls"] = "nop"
        if d["rd"] == 15:
            d["cls"] = "nop"           # plan decision D2: loads and stores of r15 are NOPs
    elif mode == 2:
        if (word >> 25) & 1:
            d["cls"] = "branch"
            d["link"] = (word >> 24) & 1
            d["imm24"] = word & 0xFFFFFF
            d["offset"] = sign_extend(d["imm24"], 24) << 2
            d["name"] = "BL" if d["link"] else "B"
        else:
            d["cls"] = "nop"           # LDM/STM: not in the subset
            d["name"] = "NOP"
    else:
        d["cls"] = "nop"
        d["name"] = "NOP"
    return d
