#!/usr/bin/env python3
"""
Instruction-fetch latency model for arm16 on a TinyTapeout 2x2 tile.

Question: which external memory is faster as instruction/data store, and by how much.
Every constant is labelled with its source. Change a constant, rerun, get the table.

Cycle counts come from the datasheets (evidence/agent_qspi_pmod_spec.md, section 5):
  W25Q128JV        Winbond  W25Q128JV Rev H / W25Q128JV-DTR Rev B
  APS6404L-3SQR    AP Memory Rev 2.1
  23LC512 protocol Microchip (the RP2 spi-ram-emu emulates it)

Definitions
  SCK     the serial clock our chip drives on the memory bus
  core    the ASIC project clock
  ratio   core cycles per SCK cycle: 2 for a toggle flip-flop, 1 for a forwarded clock
  fetch   one 32-bit ARM instruction, stored as two 16-bit words = 4 bytes
"""

CORE_HZ = 25_000_000     # target core clock, 02_arm16_fit_probe/REPORT.md
PAD_MAX_HZ = 33_000_000  # sky130_ef_io_gpiov2_pad max output frequency, tinytapeout.com/specs/gpio
MUX_RT_NS = 20.0         # measured worst-case TT mux round trip, TT3.5 silicon (same source)

class Bus:
    """pre: SCK cycles before the first data nibble/bit for a fresh, random access.
       pre_cont: same, when a command-skip mode is armed (None if the device has none).
       lanes: data lines per SCK cycle. max_sck: datasheet or firmware ceiling in Hz.
       tcem_us: max CS-low time (None if unlimited)."""
    def __init__(self, name, lanes, pre, pre_cont, max_sck, tcem_us, note):
        self.name, self.lanes, self.pre, self.pre_cont = name, lanes, pre, pre_cont
        self.max_sck, self.tcem_us, self.note = max_sck, tcem_us, note
    def data(self, bits):        return bits // self.lanes
    def per_access(self, bits):  return self.pre + self.data(bits)
    def continuous(self, bits):  return None if self.pre_cont is None else self.pre_cont + self.data(bits)
    def streaming(self, bits):   return self.data(bits)

BUSES = [
 # --- the free option: RP2 emulating a 23LC512 SPI SRAM on uio[0..3] ---------------------
 # 23LC512 READ 03h: 8 cmd + 16 addr, 0 dummy, single lane. spi-ram-emu ceiling READ <= SYS/10.
 Bus("RP2 spi-ram-emu, 23LC512 03h (SPI x1)", 1, 8+16, None, 12_500_000, None,
     "free; 64 KB; SPI only; needs custom RP2 firmware, never ported to RP2350"),

 # --- QSPI Pmod flash, W25Q128JVSIM ------------------------------------------------------
 # SPI-mode EBh: 8 cmd (single lane) + 6 addr + 2 mode + 4 dummy = 20. Continuous: 12.
 Bus("Pmod flash W25Q128, EBh SPI-mode quad I/O", 4, 20, 12, 133_000_000, None,
     "16 MB non-volatile; holds the program; continuous mode volatile, arm after reset"),
 # QPI-mode EBh with D=2 (power-on default, 50 MHz cap): 2 cmd + 6 addr + 2 dummy = 10. Continuous: 8.
 Bus("Pmod flash W25Q128, EBh QPI-mode D=2", 4, 10, 8, 50_000_000, None,
     "needs 38h Enter QPI after every power-up (volatile)"),

 # --- QSPI Pmod PSRAM, APS6404L-3SQR-SN --------------------------------------------------
 # SPI-mode EBh: 8 cmd (single lane) + 6 addr + 6 dummy = 20. No command-skip mode.
 Bus("Pmod PSRAM APS6404L, EBh SPI-mode", 4, 20, None, 109_000_000, 8.0,
     "8 MB volatile; tCEM 8 us caps a burst"),
 # QPI-mode 0Bh: 2 cmd + 6 addr + 4 dummy = 12 (66 MHz cap). QPI EBh would be 14.
 Bus("Pmod PSRAM APS6404L, 0Bh QPI-mode", 4, 12, None, 66_000_000, 8.0,
     "needs 35h Enter Quad after every power-up (volatile); what TinyQV uses"),
]

INSTR_BITS, DATA_BITS = 32, 16

def fmt(c): return "  n/a" if c is None else f"{c:5d}"

def report(ratio):
    sck = CORE_HZ / ratio
    print(f"\n{'='*100}")
    pad = "OK" if sck <= PAD_MAX_HZ else "OVER THE 33 MHz PAD RATING"
    # data launched on the falling SCK edge, sampled one full period later
    margin = 1e9/sck - (MUX_RT_NS + 6.0 + 3.0)
    print(f"core {CORE_HZ/1e6:.0f} MHz, SCK = core/{ratio} = {sck/1e6:.2f} MHz  pad: {pad}  full-period sample margin: {margin:.0f} ns     (SCK cycles | core cycles | MIPS)")
    print(f"{'='*100}")
    print(f"{'bus':<44} {'per-access':>16} {'continuous':>16} {'streaming':>16}")
    print("-"*100)
    for b in BUSES:
        cells = []
        for fn in (b.per_access, b.continuous, b.streaming):
            c = fn(INSTR_BITS)
            if c is None: cells.append(f"{'n/a':>16}")
            else:         cells.append(f"{c:>4} |{c*ratio:>5} |{CORE_HZ/(c*ratio)/1e6:>5.2f}")
        cap = "" if b.max_sck is None or sck <= b.max_sck else "  ** over device SCK cap **"
        print(f"{b.name:<44} {' '.join(cells)}{cap}")
    print()
    print("streaming = CS held low, sequential addresses, no preamble; a branch pays per-access again.")
    print("PSRAM streaming is bounded by tCEM = 8 us:", end=" ")
    for b in BUSES:
        if b.tcem_us:
            cyc = int(b.tcem_us * 1e-6 * sck)
            words = (cyc - b.pre) // b.data(INSTR_BITS)
            print(f"[{b.name.split(',')[1].strip()}: {cyc} SCK per window, {words} x 32-bit]", end=" ")
    print()

def data_table(ratio):
    print(f"\n16-bit DATA access, per-access, SCK = core/{ratio}")
    print(f"{'bus':<44} {'SCK':>5} {'core':>6}")
    for b in BUSES:
        c = b.per_access(DATA_BITS)
        print(f"{b.name:<44} {c:>5} {c*ratio:>6}")

if __name__ == "__main__":
    print(__doc__)
    for ratio in (2, 1):
        report(ratio)
    data_table(2)
    print("\nProbe RTL as written: per-access, SCK = core/2, and a wrong pin map (see REPORT.md).")
