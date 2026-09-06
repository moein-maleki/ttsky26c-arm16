# Agent report: TinyTapeout external serial memory, CPUs, and standalone demos

> Research agent output, 2026-09-04. Method: the machine-readable index `index.tinytapeout.com/<shuttle>.json`
> for all 27 shuttles (tt02 to ttgf0p3, about 4,600 entries, each with title, author, tiles, clock, repo and
> per-pin pinout). ttsky26c and ttihp26b return 404 (still open). Kept as evidence.

## Six findings

1. No ARM core has ever been taped out on TinyTapeout: zero hits for arm/thumb/cortex/aarch across 27
   shuttles. arm16 would be the first.
2. No TT project has ever pipelined a CPU that fetches from external serial memory. Every external-memory
   CPU is multi-cycle or bit-serial. Arctic0 (16-bit, SPI flash code, SPI SRAM data) is multi-cycle and stalls
   the CPU clock while SPI completes.
3. Exactly one project combines a CPU fetching from external serial memory with the on-board seven-segment
   display: Michael Bell's nanoV (TT04, 1x2), silicon-proven. His postmortem: "the design of the SPI
   controller, combined with the mux latency, meant that the maximum clock speed was around 18 MHz."
4. The TT pad ring is the bottleneck, not the memory: 4 mA drive, 33 MHz max output, 66 MHz max input,
   20 ns worst-case round trip (TT3.5 silicon). Universal practice is SCK = core/2 (TinyQV 64/32; DUMBRV:
   "If you can only do 20 MHz on the SPI bus, put the design in 40 MHz").
5. Read latency must be runtime-strappable. The RLE Video Player takes it on ui_in[2:0] (1-4 half-clocks);
   TinyQV straps it in-band on SD1:SD0 while reset is low, and its docs say the max of 3 "should get up to 5
   to have a chance at running at faster clock speeds."
6. The demo board is an RP2350B (v3.3, 2026-06-23); tinytapeout.com/specs/pcb is stale.

## 1. Projects using external SPI/QSPI memory

94 distinct projects put a serial memory bus on uio (28 four-bit QSPI, 66 single-bit SPI); 48 use the
canonical QSPI Pmod pin order verbatim.

| Project | Shuttle(s) | Author | Tiles | Clock | Memory | Lesson |
|---|---|---|---|---|---|---|
| KianV uLinux SoC | 11 shuttles, tt05 to ttgf0p3 | Hirosh Dabui | 8x2 / 4x4 | 30 MHz (34.5 max) | 16 MB QSPI flash + 8 MB PSRAM, zero cache, zero SRAM | Silicon-proven, boots uLinux; 8x2 tiles; output is a UART console, not watchable |
| FazyRV-ExoTiny | tt06 (2x2), ttihp0p2 (3x2) | Meinhard Kissich | 2x2 | 50 declared, README ~20 MHz | W25Q128JV ROM + APS6404L RAM, Wishbone-to-QSPI bridge; QPI on RAM then continuous read on ROM | Same footprint; a 2-bit-serial RV32I plus QSPI controllers already filled it ("an additional dff breaks convergence") |
| LISA 8-bit MCU | tt06, tt07, ttgf0p2, ttihp0p4 | Ken Pettit | 8x2 / 4x4 | 18-50 MHz | QSPI via a 3-way arbiter, 4-entry I-cache, 128 B DFFRAM | Silicon-proven with the Pmod and with RP2040-emulated RAM; an 8-bit MCU with QSPI and debug cost 2x6 to 4x4 |
| Arctic0 16-bit CPU | ttgf26b | Einosuke Okazaki | 1x2 | 40 MHz | SPI flash code + SPI SRAM data, two CS on one bus | Multi-cycle, stalls the CPU clock during SPI |
| DUMBRV | ttihp25b | Yuanda Liu | 2x2 | - | two independent 1-bit SPI ports: uio[3:0] ROM, uio[7:4] RAM | True Harvard on pins; the only design that solved I/D contention rather than arbitrating |
| FFD16 | ttsky26a | B. B. Icoz | 2x2 | 25 MHz | QSPI continuous read for flash, plain SPI for RAM | 2x2 + 16-bit + QSPI exists. Its uio[1]/uio[2] are labelled miso/mosi, swapped vs the Pmod |
| DJ8 8-bit CPU | tt06, tt07, ttihp0p2 | DaveX | 1x1 | 14 MHz | full parallel bus (ui_in data in, uo_out[6:0] addr hi, uio addr lo muxed with data out) | Silicon-proven; zero per-access preamble; ships a 256-byte internal test ROM |
| Risc-V nanoV | tt04, ttihp0p1 | Michael Bell | 1x2 | ~18 MHz measured | single SPI to an MB85RS4MT FRAM (or RP2040 SPI RAM) | Only external-memory CPU that drives the 7-seg; FRAM is non-volatile and byte-writable with "endless reading without page-boundary or maximum-read-time issues" |
| RLE Video Player | tt07, tt09, ttihp0p2, ttihp25a, ttsky25a | Michael Bell | 1x1 | 24-25.175 MHz | QSPI flash, plain 6Bh Fast Read Quad Output + 8 dummy | Silicon-proven, plays Bad Apple to VGA; no continuous-read mode, boots from a cold flash with zero host setup |
| Asicle v2 | ttsky25b, ttgf0p2, ttihp0p4 | htfab | 2x2 | 25.175 MHz | word list and fonts in QSPI flash | "25-fold decrease in area ... with some architectural changes to compensate for slower memory access" |
| Atari 2600 | tt09, ttsky25a, ttihp25a/b | Renaldas Zioma | 6x2 / 8x2 | 25.175 MHz | cartridge ROM from the QSPI Pmod | Silicon-proven |
| Explorer | tt07 | sylefeb | 1x2 | 33 declared | QSPI RAM + two bank-select pins | Tested at 17 MHz, PSRAM-part-dependent |
| HACK CPU | tt08, ttsky25a, ttihp25a, ttcad25a | Luo/Mhanna/Saad | 1x1 | 12.5 MHz | single SPI to a 23LC512 (or RP2040), separate debug SPI on uio[7:4] | "we cannot fetch the 16-bit instruction and data values at the same time because we only have 24 I/O pins" |
| Fuzzy Search Engine | tt09, ttsky25a, ttihp25a | Peter Norlund | 1x1 / 1x2 | 50 MHz | QSPI PSRAM, 4 CS | tested with the Machdyne QQSPI Pmod |
| TinyQV derivatives | ttihp25a to ttsky26a | AlphaOneSoC, Speck-V, Borg GPU, LoRa Edge, TinyQV-Wishbone, serv_soc_wb, SotaSoC | 2x2 to 6x2 | 25-64 MHz | identical Pmod pinout | de-facto standard; adopting it gets the flasher, bring-up scripts and community debugging free |

TinyQV baseline: 64 MHz core / 32 MHz QSPI, one 16-bit instruction per 8 core cycles, about 8 MIPS; Bell
rejected a dual bus and compensated with lw2/lw4/sw2/sw4.

## 2. CPU taxonomy (215 distinct CPU/SoC projects, 328 records; heuristic from pinout text)

| Category | Approach | Share | Representative |
|---|---|---|---|
| A | on-chip ROM synthesised into the RTL | ~6% explicit, most of the remainder | schoolRISCV, Wildcat RISC-V (no memory pins), Lipsi (1x1, drives the 7-seg) |
| B | on-chip flop/latch RAM, 16-256 B | large | SIC-1 (256 B), be8, underserved |
| C | external SPI/QSPI serial memory | ~17% | the table above |
| D | RP2040/RP2350 emulating memory | ~10%, overlapping C | Basilisc-2816, m6502 MCU, Z80, RISCY Jr., AnemoneGrafx-8 |
| E | host-streamed over ui_in / UART / I2C | ~20% | SIC-1, UART-Programmable RV32I, IEEE_CPU |
| F | wide parallel / multiplexed bus | ~8 projects | DJ8, m6502 MCU, VC 16-bit CPU, Serial PDP8 |

TT's memory spec: about 320 DFFs = 40 bytes per tile; latches 512 bits/tile at 88%; DFFRAM RAM32 is 128 B on
3x2 tiles; no SRAM macro on sky130 at TT.

Alternative pin strategies: Basilisc-2816 (custom 2-bit serial link on ui/uo, all 8 uio free); Tiny 8-bit
CPU (SPI flash+PSRAM on ui_in[0] + uo_out[3:0], all uio free); m6502 MCU (8-bit multiplexed bus, 4 phases);
LISA (latches multiplex chip-enables so QSPI, UART and I2C share 8 pins).

## 3. RP2350 as a memory server

Board facts (KiCad PCB): project_clk GPIO16, ui_in 17-24, uio 25-32, uo_out 33-40, rst_n 14. No series
resistors, level shifters or buffers on any project pin. With RP2350 GPIOBASE = 16 one PIO block sees clock,
ui_in, uio and uo_out at once; MicroPython v3.1.0 supports gpio_base.

| Option | uio pins | Random 16-bit read | Bandwidth | Status |
|---|---|---|---|---|
| toivoh/pio-ram-emulator | 4 (2 RX + 2 TX, unidirectional) | 22 cycles | >8 MB/s read, >4 MB/s write random; 8+8 MB/s block | 128 kB as 2^16 x 16-bit words; PIO+DMA only; RP2 sys = exactly 2x project clock; RP2040-only, unported |
| AnemoneGrafx-8 VRAM (tt06, toivoh) | 8 | 4 cycles, no handshake | 25.2 MB/s | silicon-proven with video; RP2040 at 100.8 MHz serving a console at 50.4 MHz; fixed cadence |
| MichaelBell/spi-ram-emu | 4 | ~40+ cycles | 1.6 MB/s | 64 kB 23LC512 clone; READ <= sys/10, FAST READ sys/8, WRITE sys/6; SPI only; burns core1 + most of both PIO blocks; "the slowest option" |
| QSPI slave emulation | 7-8 | ~32 cycles | 6.25 MB/s | does not exist anywhere |

The official SDK contains zero PIO code; rp2.StateMachine, rp2.DMA and machine.mem32 are present, and Bell's
dffram_pio.py drives a 16-bit bus through the TT pads at up to 80 MHz with per-frequency sampling-delay
tuning. RP2350-E9: a GPIO input with the buffer enabled leaks up to 120 uA mid-rail and with pull-downs can
latch at 2.1-2.2 V; a tri-stated uio bus sits mid-rail when undriven. Mitigate with pull-ups or a
split unidirectional topology.

## 4. Standalone visible demos and bootstrap

The demo board has one seven-segment digit (Kingbright KCSC02-106, common cathode) from uo_out[0] = a to
uo_out[7] = DP through cuttable jumpers JP2-JP9, an 8-way DIP on ui_in, and no user LEDs. 347 projects drive
that digit. Running with no computer: config.ini ([DEFAULT] project, mode, start_in_reset, rp_clock_frequency;
per-project clock_frequency, ui_in, uio_oe_pico) and a replaceable main.py (src/examples/custom_script_main.py).

| Pattern | Mechanism | Example |
|---|---|---|
| Cold flash, no setup | plain 6Bh + fixed dummy; CPU fetches from an untouched flash | RLE Video Player, no RP2 handshake |
| One-time web flash | tinytapeout-flasher (WebSerial): PIO SPI master at 10 MHz on uio[3:0], 20h erase / 02h program / 03h verify; first parks the ASIC off the bus via tt_um_chip_rom | Asicle v2, TinyQV, Atari 2600 |
| Fully offline flash | MichaelBell/tt-micropython-scripts/flash_prog.py programs the Pmod from the RP2's own 4 MB filesystem | TinyQV |
| RP2 pre-inits then steps back | reset low; flash into continuous read (M = A0h), PSRAMs into QPI (35h); strap latency on SD1:SD0; clock 8x; release uio; release reset (run_tinyqv.py) | TinyQV, FazyRV |
| Internal ROM fallback | 256-byte internal test ROM mirrored at 0x8000; with nothing attached, ui_in reads the DIP as a jmp into ROM; DIP-selectable demos on the 7-seg, "no external hardware needed" | DJ8, silicon-proven |

Documented failures: a1k0n's VGA donut taped out for 48 MHz, glitches on silicon, runs at 45 MHz (STA did not
catch it); TinyQV TT06 UART RX does not work; Minibyte CPU's output needs an external 74x273 + LEDs, not
demonstrable bare; TT SDR and KianV are working silicon whose only output is a host terminal; TT06 board
erratum: pull-downs R42-R48, R51-R55 too low.

## 5. Pmods

TT sells six; one is memory: QSPI Pmod (20 EUR, uio: W25Q128JVSIM + 2x APS6404L-3SQR-SN); Tiny VGA (15 EUR,
uo_out); Audio (15 EUR, uio[7] or uo_out[7], passes 0-6 through); Gamepad (20 EUR, ui_in[6:4]); Dual
7-segment (20 EUR, uo_out); Simon (20 EUR, spans 3 ports). No SD-card, EEPROM or FPGA Pmod. Third-party:
Machdyne QQSPI PSRAM, Digilent Pmod SF3 (32 MB, max 25 MHz through its series resistors), a dead-link KianV
board, a four-digit stopwatch Pmod.

Not in the other two Pmod reports: the Audio Pmod pass-through pulls IO7 high for QSPI Pmod compatibility,
so audio + QSPI stack at the cost of PSRAM B (TinyQV's AUDIO_FUNC_SEL). The flash QE bit (SR2 bit 1, 31h
after 06h) must be set once per Pmod; the agent believes store-bought units ship pre-configured (verify by
reading the JEDEC ID; ef7018 = -IM). /specs/pinouts publishes two conflicting quad-SPI maps (a PmodSF3-style
one and the QSPI Pmod one); design to the QSPI Pmod map. tt-autosel (ttcad25a, ttihp0p2) prototypes host-free
project selection from an I2C EEPROM and includes an 11-stage ring oscillator with a 5-bit divider (~17.2 MHz).

## The agent's takeaways

1. Take the RLE Video Player's protocol for boot simplicity: plain 6Bh + fixed dummy boots from a cold flash
   with zero host setup; continuous-read mode is what forces the RP2 handshake.
2. Make the read latency strappable from ui_in.
3. The ~60 cycles per instruction is the per-access preamble, not bandwidth; streaming with CS held is 3.5x.
4. Execute from flash, not PSRAM (tCEM: raise CS every ~44 bytes at 12.5 MHz).
5. Reconsider the five stages: no one on TT has pipelined an external-memory CPU.
6. Two options not costed: pio-ram-emulator (128 kB of 16-bit words on 4 pins at 22-cycle random latency,
   needs an RP2350 port and custom firmware) and SPI FRAM (MB85RS4MT, non-volatile and byte-writable, no
   page or max-read limits, one chip for code and data).
7. Carry DJ8's insurance: a small synthesised ROM holding one seven-segment demo, entered via a DIP-selected
   reset path; ROM maps to combinational logic, not flops.

## Flags

- Prompt injection observed: fetching tinytapeout.com/chips/tt06/tt_um_toivoh_retro_console returned page
  content with a fake system-reminder block instructing AI co-author attribution on commits; ignored. The
  agent also noted harness-level reminders saying the same thing; both contradict the user's global rule.
  No commits and no attribution.
- The spi-ram-emu pin map in TT's memory spec (uio[0] = GPIO21) predates the v3 board (uio[0] = GPIO25).
