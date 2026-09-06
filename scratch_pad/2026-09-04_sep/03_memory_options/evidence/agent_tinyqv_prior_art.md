# Agent report: TinyQV and external-memory CPUs on Tiny Tapeout

> Research agent output, 2026-09-04. Sources: github.com/MichaelBell/tinyQV and its shuttle wrappers, nanoV,
> the ttsky25b FemtoRV test, Mastodon posts (rebel-lion.uk/@mike, hachyderm.io/@rebelmike), two TT
> livestreams, README text, commit messages, and the TT project index. Kept as evidence.

## 1. What TinyQV is

Author Michael Bell (MichaelBell, Discord rebelmike). Repo github.com/MichaelBell/tinyQV (core) with
per-shuttle wrappers (tt06-tinyQV, ttihp-tinyQV, TinyTapeout/ttsky25a-tinyQV, tt10-tinyQV). ISA RV32EC +
Zcb + Zicond + a 32x16 multiplier plus custom mul16, lw2/lw4, sw2/sw4/sw4n; 28-bit addresses, 24-bit program
addresses, gp and tp hardwired; M-mode only. The core-only SoC is 2x2 (TT06, ttihp0p2, ttgf0p1); later
versions 3x2 (TT10, ttihp25a); crowd-sourced peripheral builds 8x4 and 4x4. Predecessor nanoV (TT04, 1x2),
bit-serial RV32E over 1-bit SPI to FRAM. The ttsky25b FemtoRV register-file test bolts Bruno Levy's parallel
FemtoRV to TinyQV's QSPI controller file-identical, proof the memory subsystem is not tied to a serial core.

## 2. How it fetches

Flash for code, PSRAM for data; code never executes from PSRAM. One W25Q128JV 16 MB flash plus two
APS6404L-3SQR 8 MB PSRAMs on mole99's qspi-pmod. QSPI, four data lines, shared bus, TT pinout (uio[0] CS0
flash, uio[1..2] SD0/SD1, uio[3] SCK, uio[4..5] SD2/SD3, uio[6..7] CS1/CS2). Multiplexed, not concurrent:
"I didn't think it was worth dedicating the pins to allow two completely separate interfaces (that would
make load/store to RAM much faster, but adds complexity and we run out of outputs)". Flash in continuous-read
mode, PSRAM in QPI mode; on TT06 the host RP2040 sets both up before release from reset (one EBh read with
M7-0 = 0xA0; 0x35 to each PSRAM). He later regretted this and added on-chip setup logic in the gf180 version.

## 3. Clocks

QSPI = core/2 always (`spi_clk_pos <= !spi_clk_pos`). 64 MHz core, 32 MHz SCK. Reason: the sky130 TT output
pad is rated 33 MHz. "TinyQV's at 64 MHz, the QSPI interface to the Pmods 32 MHz because that's basically the
limit of the outputs on Tiny Tapeout ... at 32 MHz it looks really quite dodgy, some of the clocks only
getting a little over 2 volts ... but if I go even up to 70 MHz, so 35 MHz clock coming out on the output, it
stops working."

## 4. Measured throughput

One cycle per compressed instruction, a cycle = 8 core clocks: 8 MIPS on 16-bit instructions at 64 MHz,
4 MIPS on 32-bit. Instruction table (cycles of 8 clocks): ALU 1, shift/SLT/mul 2, JAL 5, RET 5, other JALR 6,
branch not taken 1, branch taken 7, store to peripheral 1, store word to PSRAM 6-7, load word 9-10, lw2 15-16,
lw4 23-24. CoreMark 4.969 on TT06, later 5.13: "most compressed instructions take 8 clocks and uncompressed
take 16 (due to instruction fetch bandwidth). Big penalty for branches and memory access due to QSPI
transaction overheads."

| Design | Shuttle | PDK | Design clk | Measured |
|---|---|---|---|---|
| nanoV | TT04 | sky130 | - | about 18 MHz |
| TinyQV | TT06 | sky130 | 64 MHz | 64 OK; about 70 fails |
| TinyQV | ttsky25a | sky130 | 64 MHz | 90 MHz |
| TinyQV | ttihp25a | IHP | 64 MHz | 98-100 MHz |
| TinyQV | ttgf0p2 | GF180 | 24 MHz | 59 MHz |
| FemtoRV SoC | ttsky25b | sky130 | 50 MHz | 80 MHz |

## 5. The techniques

A cold EBh fast read of 4 bytes is 8 command clocks (the command is sent one bit at a time) + 6 address + 2
mode + 4 dummy + 8 data = 28. The arithmetic is right; the architecture is what is wrong.

- T1: hold CS low and keep clocking. Sequential fetch pays zero overhead; restart only on a taken branch or a
  data access (`instr_fetch_restart` gated by `!instr_fetch_running`). 28 to 8 QSPI clocks per 32-bit
  instruction, 3.5x. Everything else is second order.
- T2: stall by gating SCK low with CS held (`stall_txn`, FSM_STALLED), only at instruction boundaries.
- T3: continuous-read mode: a restart costs 12 QSPI clocks (6 addr + 2 mode + 4 dummy) instead of 20. Per
  restart, not per fetch. The W25Q128JV datasheet does not document it; "look at W25Q80 instead". M7-0 = 0xA0.
- T4: configurable input sampling delay, `delay_cycles_cfg[1:0]` (1-3), delays only the sampling point by
  1-3 core clocks; SCK never slows. Loaded from `spi_data_in[2:0]` in reset, tunable per board. "Round trip
  latency of the TT mux is a little over 20ns, so we need configurable delay cycles for reads to reach faster
  clock speeds." TT06 needed latency 2-3; ttsky25a works at 1 and 2 at 64 MHz.
- T5: drive SCK from the negedge (`spi_clk_use_neg`), delaying it half a core clock relative to the data.
  Launching SD[3:0] and SCK on the same edge violates the flash's setup time; that bug shipped in KianV, and
  the Pmod's 22 pF CLOCK cap solder bridge exists as a hardware band-aid for it. Do it in RTL.
- T6: a small circular prefetch buffer, `reg [15:0] instr_data[0:3]`, 8 bytes, with a wrap bit. No cache.
- T7: fetch fully decoupled from execute.
- T8: early JAL in decode with a private adder (JAL 5 cycles vs taken branch 7).
- T9: RET fast path from the link register's shift register (RET 5 vs JALR 6).
- T10: multi-word load/store (`data_continue` keeps CS low): 4 words 23-24 cycles instead of 38-40.
- T11: compressed instructions as a bandwidth feature; custom compressed lw/sw with tp base.
- T12: nibble-serial datapath matched to the bus width; the core is deliberately slowed to the memory, which
  is why it closes at 90-100 MHz.
- T13: SDC constraints, stable across every shuttle:

```tcl
set_clock_uncertainty 2.5 -rise_from clk -fall_to clk
set_clock_uncertainty 2   -fall_from clk -rise_to clk
set_input_delay  -max [expr $CLOCK_PERIOD * 0.65] {uio_in ui_in}
set_input_delay  -min [expr $CLOCK_PERIOD * 0.2 ] {uio_in ui_in}
set_output_delay -max [expr $CLOCK_PERIOD * 0.65] {uio_out uio_oe uo_out}
set_output_delay -min 1                           {uio_out uio_oe uo_out}
set_output_delay -max [expr $CLOCK_PERIOD * 0.2 ] {uio_out[3]}
```

65% of the period goes to IO delay on QSPI pins. He hand-instantiates `sky130_fd_sc_hd__dlygate4sd3_1` in
the register rotate path as a hold fix. Not used: DTR, cache, QSPI faster than the core.

## 6. What was hard, slow, or a mistake

- "Main bottleneck is having no instruction cache at all, and the flash speed is rather limited because the
  TT outputs are max 33MHz." DTR reads "should be a good way to go nearly twice as fast."
- TT mux crosstalk: on TT06 some 32 MHz SCK pulses reached only about 2 V. Weeks lost to ngspice on supply
  droop before tnt spotted that read data was circulating back out to tri-stated pins; capacitive coupling
  between adjacent mux wires slowed the clock rise when both neighbours fell together. Fix: shift data half
  a clock via the latency config. Lesson: "keep the data outputs constant when they are not in use."
- PSRAM tCEM avoided architecturally, not solved: "Code execution is only supported from the flash ...
  removes the need for handling the PSRAM refresh every 8us." No refresh logic in the RTL. Inference: 20 QSPI
  clocks must fit in 8 us, so QSPI >= 2.5 MHz, core >= 5 MHz; lw4 pushes it to about 11 MHz core. At 20-25 MHz
  the margin is about 2x. `qspi_ctrl.v` enforces two cycles before reselecting the same RAM (tCPH), a formal
  property in his SBY run.
- The one silicon bug: UART RX read zeros on TT06; the testbench compared against a variable it had itself
  shifted to zero, so the test passed. Found four days after the shuttle closed.
- The two PSRAMs on his Pmod are not speed-matched; one occasionally read incorrectly. Bring-up on TT06
  depended on the RP2040 configuring the memories (he forked the TT Flasher), fixed in gf180 with on-chip
  setup. UART has one byte of buffer.

## 7. Other TT CPUs executing from external memory (about 75)

- FFD16 (Bahri Berkant Icoz, ttsky26a, 2x2, 25 MHz): 16-bit, no internal program or data memory, QSPI flash
  in continuous read for fetch plus SPI PSRAM for load/store. Nearly this project's spec.
- FazyRV-ExoTiny (Meinhard Kissich, tt06 2x2 / ttihp0p2 3x2, 50 MHz): RV32I 2-bit chunk datapath, QSPI ROM +
  QSPI RAM, boot at 0x0 then continuous read.
- Arctic0 (ttgf26b, 1x2, 40 MHz, SCK 20 MHz): multicycle 16-bit, flash for code / SRAM for data, stalls the
  CPU clock during transfers.
- DUMBRV (Yuanda Liu, ttihp25b, 2x2): RV32E with two independent 1-bit SPI ports (instruction read-only,
  data read-write). Goldcrest (JKU, ttihp0p2, 6x2) and UNAL RISCV (ttsky25b, 4x2): separate SPI ROM and RAM.
- LISA (Ken Pettit, tt06/tt07/ttgf0p2, 8x2): three-channel (Q)SPI arbiter, a 4-instruction I-cache line,
  128 B DFFRAM D-cache. The cache prior art.
- Whisk (Luke Wren, tt02/tt03, 1x1): the origin; 16-bit bit-serial, SCK = CPU clock.
- underserved (Olof Kindgren, tt07, 1x2, 20 MHz): SERV from SPI flash in XIP, controller from PicoSoC.
- KianV uLinux (Hirosh Dabui, tt05/tt06+, 8x2, 30 MHz nominal, 34.5 measured): RV32IMA boots Linux 6.8 from
  16 MB QSPI flash + 8 MB PSRAM.
- Basilisc-2816 (Toivo Henningsson, tt07, 1x1): 2-bit-serial; processes each read bit as it arrives.
- RISCY Jr. (ttsky25a, 2x2): predictive next-instruction prefetch, stalls only on taken branches.
- m6502 (Chris Moos, ttihp26a, 2x2, 50 MHz): 4-phase muxed parallel bus for full 64 KB external.
- Cautionary: 8-Bit Processor with VGA (ttsky26a, 1x1) states about 100 clocks per instruction, about 200
  for load/store. That is what naive per-fetch addressing costs.

## 8. What this means for arm16 (the agent's view)

| Scheme | core clks per instr | at 25 MHz |
|---|---|---|
| Cold EBh each fetch (the probe) | about 60 | 0.42 MIPS |
| Streaming, SCK = core/2 | 16 | 1.56 MIPS |
| Streaming, SCK = core | 8 | 3.13 MIPS |
| Streaming, 16-bit instructions, SCK = core | 4 | 6.25 MIPS |

In order of leverage: (1) stream with CS held, about 3.5x; (2) SCK at the core rate: feed the chip 50 MHz,
keep Bell's controller unmodified (SCK = clk/2 = 25 MHz), clock-enable the pipeline every other cycle with
`set_multicycle_path 2`, no output-clock gating and no new clock domain; (3) 16-bit instruction encoding
(Thumb) halves fetch cost; (4) at 8-16 core clocks per fetch a 5-stage pipeline is starved 87-94% of the
time. Two things nobody on TT has done: DTR reads on the flash (EDh; TT inputs handle 66 MHz+) and a
concurrent second memory port (dedicated uo_out pins cannot tri-state, so it needs external buffering).

Start from `tinyQV/cpu/qspi_flash.v`: 146 lines, read-only flash, his note: "no longer used by TinyQV, but
is a reasonable reference for a QSPI flash controller ... it should work up to about 60MHz project clock
(30MHz QSPI clock), which is around the limit of the TT outputs anyway." Add T4 and T5 from `qspi_ctrl.v`.
