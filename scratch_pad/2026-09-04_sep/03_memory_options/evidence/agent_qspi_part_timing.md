# Agent report: QSPI flash and PSRAM read performance, datasheet numbers

> Research agent output, 2026-09-04. Sources: W25Q128JV-DTR RevC (2018-03-27, the correct sheet for the
> JVSIM), W25Q128JV RevH (2021), APS6404L-3SQR Rev 2.7 (2024-01-05), ESP-PSRAM64/64H v1.0, the TT GPIO spec
> (tinytapeout.com/specs/gpio), the TinyQV README, polpo/rp2040-psram. Kept as evidence.

## Parts on the Pmod (from the mole99/qspi-pmod BOM)

| Ref | MPN | Note |
|---|---|---|
| U1 | W25Q128JVSIM | the -IM variant: adds QPI mode and DTR; different datasheet from the JVSIQ |
| U2, U3 | APS6404L-3SQR-SN | x2, 64 Mbit each, standard grade (-40 to +85 C) |
| R1-R3 | 10k | CS pull-ups |
| C7 | 22 pF | optional footprint on SCK, normally open |

No series termination on SCK or DQ. The plain W25Q128JV datasheet never documents continuous read mode
(TinyQV README: "Bizarrely the datasheet doesn't seem to specify how to use continuous read mode"); the
W25Q128JV-DTR sheet documents it in 8.2.13.

## Table 1: W25Q128JVSIM at 3.3 V

| Transaction | Structure (SCK) | Preamble | First 32 b | +32 b | Max SCK |
|---|---|---|---|---|---|
| 03h Read Data | cmd 8 + addr 24, data x1 | 32 | 64 | 32 | 50 MHz |
| 6Bh Fast Read Quad Output (1-1-4) | cmd 8 + addr 24 + 8 dummy | 40 | 48 | 8 | 133 MHz |
| EBh Fast Read Quad I/O (1-4-4) | cmd 8 + addr 6 + M 2 + dummy | 18 (agent 5) / 20 (agent 2) | 26 / 28 | 8 | 133 MHz |
| EBh SPI continuous (M5-4 = 10) | addr 6 + M 2 + dummy | 10 / 12 | 18 / 20 | 8 | 133 MHz |
| EBh QPI, P5-4 = 00 (2 dummy) | cmd 2 + addr 6 + 2 dummy | 10 | 18 | 8 | 50 MHz |
| EBh QPI + continuous | addr 6 + 2 dummy | 8 | 16 | 8 | 50 MHz |
| DTR variants | | | | | 66 MHz |

Discrepancy note (added by the session, not the agent): agent 5 counts 2 dummy clocks after M7-0 for
SPI-mode EBh; agent 2 counts 4, which matches the RP2040 boot2 for Winbond parts (WAIT_CYCLES 4, ADDR_L 8 =
6 address + 2 mode). The session uses 20 / 12 as the conservative figures; the 2-cycle gap does not change
any conclusion.

QPI dummy clocks select the frequency cap via C0h Set Read Parameters:

| P5-P4 | Dummy | Max read at 3.0-3.6 V | at 2.7-3.0 V |
|---|---|---|---|
| 00 (default) | 2 | 50 MHz | 33 MHz |
| 01 | 4 | 80 MHz | 50 MHz |
| 10 | 6 | 104 MHz | 80 MHz |
| 11 | 8 | 133 MHz | 104 MHz |

Timing: tCLQV 6 ns max, tCLQX 1.5 ns, data setup 1 ns, hold 2 ns, tSHSL1 10 ns min. CIN 6 pF, COUT 8 pF.

## Table 2: PSRAM at 3.3 V

| Transaction | Structure (SCK) | Preamble | First 32 b | +32 b | APS6404L-3SQR max | ESP-PSRAM64H max |
|---|---|---|---|---|---|---|
| 03h Read | cmd 8 + addr 24, x1 | 32 | 64 | 32 | 33 MHz | 33 MHz |
| 0Bh Fast Read SPI | cmd 8 + addr 24 + 8 wait | 40 | 72 | 32 | 84/109 MHz | 133 MHz |
| EBh Fast Read Quad SPI (1-4-4) | cmd 8 + addr 6 + 6 wait | 20 | 28 | 8 | 84/109 MHz | 133 MHz |
| EBh Fast Read Quad QPI (4-4-4) | cmd 2 + addr 6 + 6 wait | 14 | 22 | 8 | 84/109 MHz | 133 MHz |
| 0Bh Fast Read QPI | cmd 2 + addr 6 + 4 wait | 12 | 20 | 8 | 66 MHz | n/a |
| 02h / 38h Write | cmd + addr + 0 wait | 8 or 14 | 16/22 | 8 | 84/109 MHz | 133 MHz |

Writes have zero wait cycles; quad reads have six. QPI 0Bh is capped at 66 MHz while QPI EBh runs to
109/133 MHz because 0Bh gets only 4 wait states; TinyQV picks QPI 0Bh for 2 fewer latency clocks.

| Burst mode | Max SCK | Page-boundary crossing |
|---|---|---|
| Linear Burst (power-on default) | 84 MHz | transparent, once per burst only |
| Wrap-32 (C0h toggle) | 109 MHz at 3.3 V +-10%, 133 MHz at 3.0 V +-10% | not allowed |

The -3SQR ordering table lists 84 MHz as max frequency for all -SN/-ZR orderables. Do not cite -3SQN numbers.
Timing (APS6404L / ESP-PSRAM64H): tACLK 2-5.5 / 2-6.0 ns; tCPH 18 / 50 ns; tCHD 3.0 / 20 ns; tCEM 8 us both.
CIN 6 pF, COUT 8 pF; datasheet system CL max 15 pF.

## Continuous read / XIP

Flash: yes. M5-4 = (1,0), conventionally 0xA0, in the mode byte after the address; the next EBh after CS
toggles skips the 8-bit instruction code. Exit by clocking FFh on IO0. Works in SPI and QPI. RP2040 boot2
does exactly this with these parts. PSRAM: no XIP or command-skip mechanism on either part. Both continuous
read and QPI mode are volatile device states; the flash powers up in plain SPI with continuous read off.
TinyQV has the RP2040 host arm it before releasing the core ("TinyQV expects the flash to be in continuous
read mode when the core is started").

## tCEM

8 us max CS-low for APS6404L-3SQR-SN (standard grade) and ESP-PSRAM64H; the extended -3SQRX is 3 us (revised
from 4 us in Rev 2.4). PSRAM refresh runs only while CS is high; datasheet: not raising CE# "will block internal
refresh operations and cause memory failure", i.e. data loss across the array. Budget at a 14-clock QPI EBh
preamble:

| SCK | Clocks in 8 us | Payload | 32-bit words |
|---|---|---|---|
| 25 MHz | 200 | 93 B | 23 |
| 50 MHz | 400 | 193 B | 48 |
| 84 MHz | 672 | 329 B | 82 |

Workaround: a hard word counter per burst (correct at any clock), CS high for tCPH, re-issue. TinyQV avoids
the problem by never executing from PSRAM ("Code execution is only supported from the flash ... removes the
need for handling the PSRAM refresh every 8us").

## Wrap and burst

Flash: no page-boundary penalty on reads; EBh streams linearly across 16 MB with CS held low indefinitely.
The 256-byte page constrains programming only. PSRAM: 1 KB page; linear burst crosses once per burst at up to
84 MHz; wrap-32 forbids crossing. tCEM binds before the crossing rule does.

## Worked latency, 32-bit fetch (8 data clocks; T = 40 ns at 25 MHz, 20 ns at 50 MHz)

Flash: 6Bh 48 clk = 1920 / 960 ns; EBh SPI 26 = 1040 / 520; EBh SPI continuous 18 = 720 / 360; EBh QPI 18 =
720 / 360; EBh QPI continuous 16 = 640 / 320.
PSRAM: EBh SPI 28 = 1120 / 560; EBh QPI 22 = 880 / 440; 0Bh QPI 20 = 800 / 400.
Add 1-2 clocks CS overhead per transaction plus tSHSL1 10 ns (flash) or tCPH 18 ns (PSRAM).

Marginal cost decides the microarchitecture: sequential words cost 8 clocks with CS held low.

| Burst | Flash QPI continuous | ns per instruction at 25 MHz |
|---|---|---|
| 1 word | 16 clk | 640 |
| 4 words | 8 + 32 = 40 clk | 400 |
| 8 words | 8 + 64 = 72 clk | 360 |

At 25 MHz 1:1 a random fetch is 16 core cycles and a sequential prefetched one is 8. A 2-4 word prefetch
FIFO is the single highest-leverage block. At 50 MHz, QPI with P5-4 = 00 sits exactly on the 50 MHz rating;
SPI-mode continuous (18 clk, 133 MHz) or P5-4 = 01 (18 clk, 80 MHz) land on the same count, so QPI's 2-clock
advantage only exists at 25 MHz and below.

## Realistic clock ceiling: the TT sky130 pad, 33 MHz

TT GPIO spec for sky130_ef_io_gpiov2_pad: max output frequency 33 MHz, max input 66 MHz, 4 mA drive. "In
practice, you can output a 33 MHz square wave and it still looks acceptable, albeit with some asymmetry, if
the load isn't large." "People have driven the clock line of the QSPI Pmod at 32 MHz successfully." Measured
worst-case round-trip latency through the TT mux: 20 ns (TT3.5 silicon, ~22 C), under 2 ns pin-to-pin variance.

Round trip: mux 20 + tCLQV 6.0 = 26 ns (flash); mux 20 + tACLK 5.5 = 25.5 ns (PSRAM); plus ~3 ns internal
setup = ~29 ns. Sampling one full SCK period after the launch edge: T >= 29 ns, f <= ~34 MHz. Sampling a half
period later (naive mode 0): T/2 >= 29 ns, f <= ~17 MHz. Avoid the half-period trap.

Recommendation: SCK at 20-25 MHz, 1:1 with the core clock. Do not build a core/2 divider.

Corroboration: TinyQV (same Pmod, same flow, tt06 / ttsky25a / ttihp25a) runs a 64 MHz core with QSPI at
32 MHz; its author notes STA passes at 100 MHz but "it is likely not to actually work that fast due to the
slow TT outputs". polpo/rp2040-psram reached 140 MHz effective to APS6404L parts at a 280 MHz RP2040 core,
but only with a hand-written PIO engine, falling-edge sampling and an extra fudge cycle, on a tight PCB.

Board derating: three devices on the shared DQ bus put 3 x 8 pF = 24 pF before trace and header, above the
PSRAM's 15 pF system CL, so the 109/133 MHz figures are unreachable here. No series termination; the
unpopulated 22 pF SCK footprint exists to slow the clock edge if ringing appears. Use a short header-to-header
adapter, not ribbon.

## Flag on the probe RTL

`02_arm16_fit_probe/rtl/qspi_master.v` shifts {8'h6B, addr[15:0], 8'h00} out 4 bits per clock, but 6Bh in SPI
mode is 1-1-4 (opcode and address single-lane, 24-bit address, 8 dummy clocks). It implements a QPI-shaped
transaction wearing a 6Bh opcode. It toggles the clock every core cycle, so SCK = core/2 and a fetch is 22 QSPI
clocks = 44 core cycles. Retargeting to QPI EBh continuous at SCK = core gets 16 core cycles, 2.75x, for a
controller rewrite and no area of consequence.
