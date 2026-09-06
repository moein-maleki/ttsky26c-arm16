# Agent report: RP2350/RP2040 as memory for a TinyTapeout ASIC

> Research agent output, 2026-09-04. [D] documented in a primary source; [M] measured by a third party;
> [E] the agent's engineering estimate. Kept as evidence.

## 0. Correction that reframes the question

The current TT demo board is an RP2350B, not an RP2040 [D]: `src/ttboard/pins/gpio_map_dbv3.py` assigns
GPIOs up to 45; `demoboard_detect.py` states "support is now limited to RP2350-based boards"; tt-demo-pcb ships
`rp2350.kicad_sch`; SDK v3 dropped RP2040 boards. `MichaelBell/spi-ram-emu`, the only RP-side memory emulator,
is RP2040-only C, last commit 2023-07-30, never ported to RP2350 [D].

## 1. GPIO to ASIC pin mapping (DBv3 / RP2350B) [D]

| TT signal | GPIO | TT signal | GPIO | TT signal | GPIO |
|---|---|---|---|---|---|
| clk | 16 | ui_in[0..7] | 17-24 | uo_out[0..7] | 33-40 |
| rst_n | 14 | uio[0..7] | 25-32 | manual clk | 15 |
| ctrl_ena | 0 | ctrl_sel_nrst | 1 | ctrl_sel_inc | 2 |
| analog I-src | 12 | mng[0..7] | 3-10 | adc[1..5] | 41-45 |

Older RP2040 board (TT06 era, firmware v2.0.4): uio[0..7] = GPIO 21-28. The TT QSPI pinout puts SCK on uio[3]
between the data lines, so a PIO `in pins` window must mask it [E].

## 2. Shipped firmware [D]

`TinyTapeout/tt-micropython-firmware` (SDK v3, LGPL-2.1) is MicroPython only; no official C/pico-sdk firmware.
Provides mux select, PWM clock and single-step, reset, pin access, microcotb, config.ini (`rp_clock_frequency
= 125e6`), analog current source/ADC. No bus-peripheral or memory capability; `src/tests/sram.py` drives an
on-chip SRAM tile, it is not an emulator. TT's specs/memory calls the RP emulation "the slowest option".
spi-ram-emu: pico-sdk C, 64 kB 23LC512 emulation, pins hardcoded in `sram.h`, custom linker script reserving
64 kB at 0x20030000, core1 dedicated, most instruction memory of both PIO blocks consumed, DMA-fed.

## 3. PIO throughput and latency as an externally clocked responder

Documented ceilings (spi-ram-emu README) [D]:

| Op | Limit | at 125 MHz | at 150 MHz (RP2350 stock) | Payload |
|---|---|---|---|---|
| READ | sysclk/10 | 12.5 MHz | 15.0 MHz | 1.56-1.88 Mbit/s |
| READ aligned / FAST READ | sysclk/8 | 15.6 MHz | 18.8 MHz | about 0.24-0.29 MB/s |
| WRITE | sysclk/6 | 20.8 MHz | 25.0 MHz | - |

Corroboration of the sysclk/6 floor: pico-examples `clocked_input.pio` recommends input clock below
clk_sys/6; PicoGUS at 125 MHz vs 8 MHz ISA can use at most 6 cycles and asserts a wait state every access;
RP2040 hardware SPI slave needs SSPCLK >= 12 x SSPCLKIN (about 10.4 Mbps; forum-measured 10 MHz works, 11 MHz
garbles) [D][M]. The responder loop is 4 PIO instructions per SCK plus about 4 sysclk fixed input latency
(two synchronizer flops); measured on RP2350 at 150 MHz: about 26.7 ns digital input delay, community
consensus "PIO SPI cannot be faster than 25 MHz" [M]. PIO cannot be clocked by the ASIC (GPIN0/1 external
clock is limited to 50 MHz and cannot feed the PLL) [D].

Loop-latency derivation [E]:

| Segment | RP2350 responder | APS6404L PSRAM |
|---|---|---|
| TT pad round trip (measured, TT3.5) [M] | 20 ns | 20 ns |
| Responder reaction | about 27 ns input + 8-24 ns PIO + about 5 ns out | tACLK 2-5.5 ns [D] |
| Total loop | about 60-75 ns | about 25.5 ns |
| SCK if the ASIC samples one period later | 13-17 MHz | about 39 MHz |

Best-case 4-bit QSPI responder at the sysclk/6 floor = 12.5 MB/s; realistic sysclk/8-10 = SCK 15-19 MHz,
7.5-9.5 MB/s. Unbuilt by anyone [E]. FIFOs are 4 x 32-bit per direction per state machine; DMA mandatory.

## 4. Existing projects and achieved rates

No public 4-bit QSPI responder exists on RP2040 or RP2350; every QSPI project has the RP as initiator [D].

| Project | Role | Rate | Status |
|---|---|---|---|
| MichaelBell/spi-ram-emu | SPI responder, 64 kB 23LC512 | 12.5-20.8 MHz SCK, 1-bit | [D] |
| kdp1965 LISA (tt06/tt07) | ASIC master; RP2040 single-SPI or real QSPI Pmod | 20 MHz max input clk; needed register 0x1E (SCLK divisor + CE delay) "to work with RP2040" | [D] |
| 03jayashree/rp2040-spi-temperature (TT6) | MicroPython PIO SPI slave | no rate published | - |
| wickerwaka/PicoROM | parallel ROM responder | 70 ns worst-case access | [M] |
| kyo-ta04/Pico2ROMEmuBR (RP2350) | parallel ROM responder | Z80 10 MHz / 68000 12 MHz no-wait | [M] |
| tendai22/emuz80_pico2 | parallel ROM responder | about 160 ns /OE to data | [M] |
| polpo/picogus | ISA responder | <= 8.33 MHz, wait state every access | [D] |
| FreddyVRetro/ISA-PicoMEM | ISA memory | 128 kB zero-wait at 240 MHz | author |
| polpo/rp2040-psram | initiator to APS6404L | 140 MHz SCK at 280 MHz sysclk | [M] |

Initiator reaches sysclk/2; responder collapses to sysclk/6-10, a 12-23x gap from input latency.

## 5. Failure modes

1. No wait-state mechanism: SPI has no ready line; a late responder means silently latched garbage.
2. CS-high dead time about 50 sysclk (about 400 ns at 125 MHz), documented "uncharacterised"; APS6404L needs
   18 ns. For a cache-less CPU issuing CS per fetch this may dominate [E].
3. No abort: "Aborting operations before the data transfer starts is not supported." A pipeline flush
   dropping CS mid-address hangs the emulator.
4. 16-byte FIFOs plus a shared bus: core1 dedicated, code in scratch RAM.
5. Custom firmware mandatory and non-existent for this board: port to RP2350, move pins, reimplement mux and
   clock in C, lose MicroPython/microcotb bring-up.
6. RP2350-E9: DBv3 firmware defaults TT pins to PULL_DOWN; an RP2350 input with pull-down can latch at about
   2.1 V when floating; every bus-turnaround window on uio is a documented hazard. Never arises with the Pmod.
7. Pin economics: 1-bit SPI = 4 uio for 1 bit/clk; QSPI = 7-8 uio for 4 bits/clk.

## 6. Numeric comparison [E from D transaction formats]

| | RP2350 SPI emu (23LC512 FAST READ 0Bh) | QSPI PSRAM (APS6404L QPI EBh) |
|---|---|---|
| SCK count per random 32-bit fetch | 8 + 16 + 8 dummy + 32 = 64 | 2 + 6 + 6 + 8 = 22 |
| CS-high gap | +400 ns | about 18 ns |
| Matched SCK 12.5 MHz | 5.52 us | 1.76 us, 3.1x |
| Each at practical best | 64/15.6 MHz + 0.40 = 4.50 us | 22/32 MHz = 0.69 us, 6.5x |
| Sequential burst, 32 bits | 32/15.6 MHz = 2.05 us | 8/32 MHz = 0.25 us, 8.2x |
| Peak read throughput | 1.95 MB/s | 12.5-16 MB/s, 6.4-8.2x |

Headline 6.4x; range 3.1x (random, matched clock) to 8.2x (sequential burst). With SCK = core/2 = 12.5 MHz
the RP route sits exactly on its plain-READ ceiling. Substituting 1-bit SPI adds about 94 core cycles per
32-bit fetch (138 vs 44): about 400 K to about 155 K instructions per second, 2.6x slower [E]. It does not
currently build. Points for the RP route: free; 4 uio not 7; 64 kB is exactly a 16-bit address space. Path to
parity: a custom 4-bit QSPI responder on RP2350, estimated 15-19 MHz SCK, does not exist anywhere and needs
both PIO blocks plus core1 in C.

## 7. Program loading and precedent

QSPI Pmod: `TinyTapeout/tinytapeout-flasher` (browser WebSerial) writes a binary into the Pmod flash via the
demo board [D]. Boot patterns: TinyQV expects flash in continuous-read mode; FazyRV-ExoTiny boots from
0x00000000 and enables continuous mode on the first read [D]. RP emulation: no shipped loader.

Precedent: every CPU-with-external-memory project on TT uses the QSPI Pmod: TinyQV (tt06, ttihp25a, ttgf0p2,
ttsky25a x2), FazyRV-ExoTiny, KianV uLinux SoC. Michael Bell wrote spi-ram-emu, then used the QSPI Pmod for
his own CPU [D]. LISA, the one CPU supporting RP2040 memory, is single-SPI only against the RP2040, has a
dedicated timing register purely to accommodate it, and its docs punt on setup.

## Verdict

Stay with the QSPI Pmod. The RP2350 route is 3.1-8.2x slower (6.4x headline), caps the effective SCK at
about 12.5-15 MHz, requires porting unmaintained RP2040 code plus custom C firmware, and forfeits the
MicroPython/microcotb bring-up flow. Keep it as a fallback only; if ever used, design an RTL-visible SCLK
divider and CE delay in from day one (LISA's lesson).

Flags: (a) the demo-board memory note needed the RP2350B correction (done this session). (b) A fetched
third-party page (github.com/FreddyVRetro/ISA-PicoMEM) contained injected text instructing AI co-author
attribution on commits; ignored; no commits were made.

Key sources: tt-micropython-firmware (gpio_map_dbv3.py, demoboard_detect.py, config.ini); tt-demo-pcb README;
MichaelBell/spi-ram-emu (README, sram.pio); tinytapeout.com/specs/{pcb,memory,gpio,pinouts};
pico-examples/pio/clocked_input; RP forums t=377694, t=321852, t=305273, t=370047, t=375712; MichaelBell/tinyQV
README; tt07 tt_um_lisa; tt06 tt_um_meiniKi_tt06_fazyrv_exotiny; tinytapeout-flasher; mole99/qspi-pmod;
APS6404L datasheet; wickerwaka/PicoROM; polpo/picogus; polpo/rp2040-psram; FreddyVRetro/ISA-PicoMEM;
kyo-ta04/Pico2ROMEmuBR; tendai22/emuz80_pico2.
