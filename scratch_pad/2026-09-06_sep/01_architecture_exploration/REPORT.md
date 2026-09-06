# What earns its cycles: forwarding, branches, parallel memory, latch caches, and tnt's register file

> 2026-09-06. Architectural exploration before RTL, at the user's request. Method: the probe RTL read for
> its stall wiring, a cycle model (`scripts/`), two research sweeps of the TinyTapeout ecosystem and two
> planning reviews (`evidence/`), on top of this week's measured areas. Decisions: the chip stays on
> TTSKY26c with the spec (now v0.3); the ROM outranks the UART in the drop order.

## 1. The probe has no stall policy, and the policy decides everything

`IF_stage_reg.v` reloads from the fetch stage every cycle unless frozen, and the only freeze sources are a
data access or a hazard. When the fetch is not ready the same instruction re-enters decode every cycle,
and `instr_req_out = ~freeze_in` re-requests the same address after a freeze while the streaming
controller pulses ready for one cycle, so a word delivered during a freeze is fetched again and executed
twice. The flush bubble is an all-zero word, which decodes as `ANDEQ r0, r0, r0` with a write enable. The
design must choose a policy:

- Drain: older instructions keep flowing; a bubble (condition 0b1111) enters decode. A branch resolves two
  cycles after it arrives and aborts the fetch in flight; a load issues three cycles after arrival.
- Freeze: all stages hold. Each instruction advances one stage per arrival; a branch resolves only after
  the next word is fetched, and that fetch is wasted.

| Configuration | straight-line | loop-heavy (0.20, 0.10, 0.40) | load-heavy (0.10, 0.30, 0.40) |
|---|---|---|---|
| freeze, F16 R40, no forwarding | 16.6 | 43.2 | 60.0 |
| freeze, F16 R40, forwarding | 16.3 | 42.8 | 59.6 |
| drain, F16 R40, with or without forwarding | 16.0 | 33.5 | 47.5 |
| drain, F16 R24, continuous read armed | 16.0 | 28.7 | 41.1 |
| drain, F16 R24, one-entry branch-target cache | 16.0 | 25.5 | 39.5 |
| drain, F8 R12, memory clock = core clock | 8.0 | 14.7 | 21.1 |
| drain, F8 R12, one-entry branch-target cache | 8.0 | 13.1 | 20.3 |
| program on chip, no forwarding | 1.6 | 1.8 | 1.8 |
| program on chip, forwarding | 1.0 | 1.0 | 1.0 |

F = core cycles per streamed instruction, R = stream restart, mixes are fractions of taken branches,
loads or stores, and adjacent dependencies. Drain is mandatory: freeze costs 30% more on loops and loads.

## 2. Forwarding, hazard detection and branch prediction

Under drain, forwarding and hazard detection never fire on the streamed path: the previous instruction
has retired before the next arrives. They measure 64 cells, 0.9% of the tile. They are worth 40 to 80% the
moment instructions arrive back to back, which happens from the internal ROM and from any on-chip program
store. Verdict: keep them, latch the FWD_EN switch at reset, and make the ROM demo a program with a
dependent chain so flipping the switch visibly changes its speed. Branch prediction is not worth a gate:
the cost of a taken branch is the stream restart, which no predictor removes. What removes part of it is
the flash's continuous-read mode (restart 20 to 12 memory clocks) and caching the first instruction at
the target (hides one fetch per hit). No TinyTapeout CPU has a branch predictor or a published CPI with
and without forwarding; the model above is the only quantification.

## 3. Parallel instruction and data memory

| Scheme | Pins | Rate | Random latency | Needs | Status |
|---|---|---|---|---|---|
| QSPI Pmod on the shared bus, as specified | 8 bidirectional | 4 bits per clock | 16-bit load about 88 core cycles with the restart | nothing | silicon-proven widely |
| toivoh `pio-ram-emulator`, the board MCU serving 64K x 16 bits | 2 outputs + 2 inputs | over 8 MB/s random | 22 clocks start to start | MCU firmware at 2x the design clock; RP2040 only | proven on ttihp25a; not ported to the RP2350 board |
| AnemoneGrafx-8 VRAM server | all 8 bidirectional | 25 MB/s, fixed cadence | about 12 clocks | same family | tt06 silicon; collides with the flash |
| DUMBRV, two 1-bit SPI buses | 4 + 4 bidirectional | 1 bit per clock each | 8 + 16 clocks | plain SPI chips | ttihp25b, no silicon yet |
| Multiplexed parallel bus to the MCU (Simplified 6502) | all 24 pins | about 20 MB/s | 2 clocks | a bus server | ttsky25a |

The one path that fits beside the flash is the two-wire emulator channel: loads about 22 to 30 cycles and
no stream break, for two outputs, two inputs, a one-bit-per-colour VGA, and firmware nobody has ported.
Parked. "Data as if from SRAM" is delivered instead by running the demo from on-chip ROM with data in
registers and peripherals. Self-arming continuous read is free in the controller (FazyRV-ExoTiny) but
needs an FFh mode reset after every chip reset, because reset does not reset the flash. Multi-word loads
(TinyQV) cut 36 to 40% per word. Nobody on the platform keeps two flash streams open, uses DTR reads, or
buffers writes.

## 4. Dense storage on sky130 at TinyTapeout

| Option | Density | Maturity | Path |
|---|---|---|---|
| Flop cache with tags (measured) | 0.018 bits/um^2; 4 instructions = 14% of the tile | proven | RTL |
| Latch RAM, Bell tt06 | 0.0285 bits/um^2; 4 instructions 6%, 8 instructions 12% | silicon-proven | RTL plus explicit gating cells, half-cycle gate, no back-to-back writes |
| tnt `rf_top`, 32 x 32, 1 write + 2 read ports | 0.065 bits/um^2; 15,744 um^2 = 22% of the tile | proven via FemtoRV at 80 MHz | hard macro in a Verilog project; license unresolved |
| ROM macro (tnt, urish) | 1.51 bits/um^2; 256 instructions about 7.5% | proven on ttsky25a, 10 ns | hard macro; contents fixed at tapeout |
| C4M full-custom SRAM, 128 bytes in a 1x1 | about 0.057 bits/um^2 | on ttsky26a, silicon not back | full custom |
| DFFRAM RAM32 | 0.019 bits/um^2 | proven | needs a 3x2 |

A latch is 25% smaller than a flop (15.0 vs 20.0 um^2); Bell's 1.6x comes from sharing gate and mux. A
cache or loop buffer of useful size does not fit beside the core, VGA and UART. A ROM macro is the one
structure that changes the game: a demo program on chip runs at one instruction per cycle, the only way
this chip runs without stalls, and the only path where forwarding earns its area.

## 5. `tt_um_tnt_rf_validation`

A 1x2 harness around tnt's `rf_top`, hand-drawn bit cells and decoders with sky130 latches around them,
132.64 x 118.70 um, too tall for a 1x1. Its own results are unpublished; the macro is proven through
FemtoRV. Reuse is a `MACROS` block with power on met3 and relaxed PDN checks. It has exactly an ARM
register file's ports but saves only a few percent on a 16-bit datapath; its value is a 32-bit datapath
on a 2x2, a different chip. Parked.

## 6. What changed in the spec (v0.3) and what is parked

Folded in: the drain policy with a valid/ready fetch and 0b1111 bubbles; forwarding kept and documented
as live only in ROM mode, FWD_EN latched at reset; the internal ROM promoted above the UART, isolated from
the controller, with a dependent-chain demo program; the controller written around a parameterized
memory-clock tick; the model's CPI as the expectation; the counters as a retired-per-frame meter; the RTL
rules (one reset style, the lab's memory offset removed, X-containment, one transaction per access, a
negative test).

Parked for the follow-on chip, ranked by risk: tnt's macro, the emulator channel, the ROM macro, the latch
buffer, clock forwarding (the return-data window at 25 MHz admits one strap setting; a strappable ratio is
the mitigation), continuous read, the branch-target cache, decode-stage branches. Two tracks: sky130 26d
(ROM macro demo at one instruction per cycle, 73 to 77% on a 2x2 or 47% on a 3x2) or the next IHP shuttle
(the 512x16 SRAM cache on a 3x2).

## 7. The biggest risk to the chip working first time

The QSPI path end to end, where every external-memory CPU on this platform had its silicon problem. The
ROM mode, isolated from the controller, is the insurance, which is why it outranks the UART. Mitigations
in order: the controller from TinyQV's proven structure with the sampling delay and falling-edge launch;
SCK at core/2 with the strap; edge-accurate flash and PSRAM models with the mux round trip swept 0 to
40 ns; a transaction-count check and a negative test; gate-level replay with the `uio` slack read by hand.
