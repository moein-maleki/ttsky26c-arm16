"""arm16 golden model: the instruction subset, the address map and the peripherals of docs/spec.md,
written from the ARM architecture definition and not from the RTL (spec 14.1).

Semantics on 16 bits: registers r0 to r14, r15 is the program counter; reads of r15 return PC + 8;
branch target = PC + 8 + (imm24 << 2); BL writes r14 = PC + 4; a data-processing write to r15 branches
to the result. Flags follow the ARM definition on 16 bits: N = bit 15, Z, C = carry out on addition and
NOT borrow on subtraction, V = signed overflow; logical operations and the shifter leave C and V (plan
decision D1). General registers are not reset (spec 10): they start with a recognisable pattern.
"""

import hashlib

from arm16_asm import decode, rotate_right_16

MASK = 0xFFFF

# peripheral registers (spec 3.4), addresses 0xFF00 + offset
VGA_VAL, SW, UART_DATA, UART_STAT, UART_DIV, METER, VGA_FG, VGA_BG = 0x00, 0x02, 0x04, 0x06, 0x08, 0x0C, 0x10, 0x12


def condition_met(cond, n, z, c, v):
    return {
        0: z, 1: not z, 2: c, 3: not c, 4: n, 5: not n, 6: v, 7: not v,
        8: c and not z, 9: (not c) or z, 10: n == v, 11: n != v, 12: (not z) and (n == v),
        13: z or (n != v), 14: True, 15: False,
    }[cond]


def shift_operand(value, kind, amount):
    """Operand 2 register form under plan decision D1 (literal amounts on 16 bits, no #0 special cases)."""
    value &= MASK
    if kind == 0:                                   # LSL
        return (value << amount) & MASK if amount < 16 else 0
    if kind == 1:                                   # LSR
        return value >> amount if amount < 16 else 0
    if kind == 2:                                   # ASR
        sign = value & 0x8000
        if amount >= 16:
            return MASK if sign else 0
        return ((value >> amount) | ((MASK << (16 - amount)) & MASK)) & MASK if sign else value >> amount
    return rotate_right_16(value, amount)          # ROR


class Arm16Model:
    def __init__(self, flash, boot_rom=None, fwd_en=True, sw=0):
        self.flash = bytes(flash) + b"\xff" * max(0, 32768 - len(flash))
        self.boot_rom = list(boot_rom) if boot_rom else None
        self.fwd_en = fwd_en
        self.regs = [(0xA000 | (i << 4) | i) & MASK for i in range(15)]   # unreset, recognisable
        self.pc = 0
        self.n = self.z = self.c = self.v = False
        self.psram = bytearray(32768)
        self.vga_val, self.vga_fg, self.vga_bg = 0, 0x3F, 0
        self.uart_div = 217
        self.sw = sw & 0xFF
        self.uart_tx_bytes = []
        self.uart_rx_queue = []
        self.rx_valid = False
        self.rx_overrun = False
        self.rx_byte = 0
        self.meter = 0
        self.retired = 0
        self.bus_transactions = 0
        self.stores = 0
        self.loads = 0
        self.trace = []

    # ------------------------------------------------------------------ memory and peripherals
    def fetch(self, pc):
        if self.boot_rom is not None:
            return self.boot_rom[(pc >> 2) % len(self.boot_rom)] & 0xFFFFFFFF
        if pc & 0x8000:
            raise RuntimeError("fetch from the PSRAM or peripheral range at 0x%04X is not supported" % pc)
        return int.from_bytes(self.flash[pc & 0x7FFC:(pc & 0x7FFC) + 4], "little")

    def read16(self, addr):
        addr &= 0xFFFE
        self.loads += 1
        if addr >= 0xFF00:
            return self.read_peripheral(addr - 0xFF00)
        self.bus_transactions += 1
        if addr < 0x8000:
            return int.from_bytes(self.flash[addr:addr + 2], "little")
        off = addr - 0x8000
        return int.from_bytes(self.psram[off:off + 2], "little")

    def write16(self, addr, value):
        addr &= 0xFFFE
        value &= MASK
        self.stores += 1
        if addr >= 0xFF00:
            self.write_peripheral(addr - 0xFF00, value)
            return
        if addr < 0x8000:
            return                                   # a store to the flash range does nothing, no bus
        self.bus_transactions += 1
        off = addr - 0x8000
        self.psram[off:off + 2] = value.to_bytes(2, "little")

    def read_peripheral(self, off):
        if off == VGA_VAL:
            return self.vga_val
        if off == SW:
            return self.sw
        if off == UART_DATA:
            value = self.rx_byte
            self.rx_valid = False
            self.rx_overrun = False
            return value
        if off == UART_STAT:
            return (1 if self.rx_overrun else 0) << 2 | (1 if self.rx_valid else 0) << 1   # TX_BUSY = 0 in the model
        if off == UART_DIV:
            return self.uart_div
        if off == METER:
            return self.meter
        if off == VGA_FG:
            return self.vga_fg
        if off == VGA_BG:
            return self.vga_bg
        return 0

    def write_peripheral(self, off, value):
        if off == VGA_VAL:
            self.vga_val = value
        elif off == UART_DATA:
            self.uart_tx_bytes.append(value & 0xFF)
        elif off == UART_DIV:
            self.uart_div = value
        elif off == VGA_FG:
            self.vga_fg = value & 0x3F
        elif off == VGA_BG:
            self.vga_bg = value & 0x3F

    def uart_receive(self, byte):
        """A byte arrives on the serial line (testbench side)."""
        if self.rx_valid:
            self.rx_overrun = True
        self.rx_byte = byte & 0xFF
        self.rx_valid = True

    # ------------------------------------------------------------------ registers
    def reg(self, r):
        if r == 15:
            return (self.pc + 8) & MASK
        return self.regs[r]

    # ------------------------------------------------------------------ execution
    def step(self):
        """Execute the instruction at pc. Returns the decoded instruction."""
        word = self.fetch(self.pc)
        d = decode(word)
        d["pc"] = self.pc
        if d["valid"]:
            self.retired += 1          # a word with condition 1111 is a bubble, never an instruction
        next_pc = (self.pc + 4) & MASK
        if d["valid"] and condition_met(d["cond"], self.n, self.z, self.c, self.v) and d["cls"] != "nop":
            next_pc = self._execute(d, next_pc)
        self.trace.append(d)
        self.pc = next_pc
        return d

    def _operand2(self, d):
        if d["i"]:
            return rotate_right_16(d["imm8"], 2 * d["rot"])
        return shift_operand(self.reg(d["rm"]), d["shift_type"], d["shift_amount"])

    def _execute(self, d, next_pc):
        if d["cls"] == "dp":
            return self._dp(d, next_pc)
        if d["cls"] == "ldst":
            base = self.reg(d["rn"])
            addr = (base + d["imm12"]) & MASK if d["u"] else (base - d["imm12"]) & MASK
            if d["l"]:
                self.regs[d["rd"]] = self.read16(addr)
            else:
                self.write16(addr, self.reg(d["rd"]))
            return next_pc
        if d["cls"] == "branch":
            if d["link"]:
                self.regs[14] = (self.pc + 4) & MASK
            return (self.pc + 8 + d["offset"]) & MASK
        return next_pc

    def _dp(self, d, next_pc):
        name = d["name"]
        a = self.reg(d["rn"])
        b = self._operand2(d)
        cin = 1 if self.c else 0
        write = name not in ("CMP", "TST")
        arith = None
        if name == "AND" or name == "TST":
            r = a & b
        elif name == "EOR":
            r = a ^ b
        elif name == "ORR":
            r = a | b
        elif name == "MOV":
            r = b
        elif name == "MVN":
            r = (~b) & MASK
        elif name == "ADD":
            arith = a + b
        elif name == "ADC":
            arith = a + b + cin
        elif name == "SUB" or name == "CMP":
            arith = a + ((~b) & MASK) + 1
        elif name == "SBC":
            arith = a + ((~b) & MASK) + cin
        else:
            raise AssertionError(name)
        if arith is not None:
            r = arith & MASK
            if d["s"]:
                self.c = arith > MASK
                if name in ("ADD", "ADC"):
                    self.v = ((a ^ b) & 0x8000) == 0 and ((r ^ a) & 0x8000) != 0
                else:
                    self.v = ((a ^ b) & 0x8000) != 0 and ((r ^ a) & 0x8000) != 0
        if d["s"]:
            self.n = bool(r & 0x8000)
            self.z = r == 0
        if write:
            if d["rd"] == 15:
                return r & 0xFFFC
            self.regs[d["rd"]] = r
        return next_pc

    def run(self, max_instr=100000, stop_at_self_branch=True):
        """Run until a self-branch is executed (a taken B to its own address) or max_instr."""
        for i in range(max_instr):
            pc = self.pc
            d = self.step()
            if stop_at_self_branch and d["cls"] == "branch" and self.pc == pc and d["valid"] \
                    and not d["link"]:
                return i + 1
        return max_instr

    def flags_word(self):
        return (8 if self.n else 0) | (4 if self.z else 0) | (2 if self.c else 0) | (1 if self.v else 0)

    def state_digest(self):
        return {
            "regs": list(self.regs),
            "flags": (self.n, self.z, self.c, self.v),
            "flags_word": self.flags_word(),
            "pc": self.pc,
            "psram_sha1": hashlib.sha1(bytes(self.psram)).hexdigest(),
            "vga_val": self.vga_val, "vga_fg": self.vga_fg, "vga_bg": self.vga_bg,
            "uart_tx": list(self.uart_tx_bytes),
            "retired": self.retired,
            "bus_transactions": self.bus_transactions,
        }
