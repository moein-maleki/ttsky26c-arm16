# Planning review, performance-first (2026-09-06)

Scoring: cycles moved in the model, tile percentage, what could stop the chip. 1% of the tile = 726 um^2 placed.
Three facts: on the flash path the CPI floor is F (only the clock ratio, the restart R, and taking instructions
off the bus move it); under drain forwarding never fires on the flash path; headroom is 1 to 3 points (base
about 71.2% after the controller rewrite, VGA and peripherals).

## Ranked features

| # | Feature | Moves (S / L / LD) | Area | Main risk | Verdict |
|---|---|---|---|---|---|
| 1 | Drain policy, valid/ready fetch, bubbles | 16.0 / 33.5 / 47.5 vs freeze about 16 / 44 / 62 | 0 to -0.5% | pipeline-control wiring; caught by the differential tests | v1 and v2; at F >= 8 the fetch buffer cannot overflow, so no SCK-gated stall is needed |
| 2 | SCK 1:1 by forwarding the core clock through an ICG (dlclkp_1), data launched on negedge, capture strappable, SAFE strap back to core/2 | 16.0 / 28.7 / 41.1 to 8.0 / 14.7 / 21.1; halves everything | about +0.5% | the forwarded clock through the TT mux and its STA; nibble validity shrinks to 40 ns; the same margin model gives TinyQV 2 ns at 32 MHz and it works, so the model is conservative by at least 10 ns; Whisk is the only SCK = core precedent | v2, highest gain per area; alternatives: 50 MHz core with clock enables (multicycle SDC risk), or DTR EDh at core/2 (the Pmod flash is the JVSIM DTR part; zero TT precedent) |
| 3 | Self-armed continuous read: boot FSM sends FFh FFh with IO high (mode reset), then EBh with M = A0h | R40 to R24: -14% / -13%; prerequisite for R12 | about +0.2% | volatile mode after a warm reset (the FFh reset covers it); the JV-DTR sheet 8.2.13 documents the mode; SAFE strap disables | v2 |
| 3b | PSRAM QPI (35h, 0Bh, 02h, F5h exit at boot) | data access 24 to 16 SCK; at F8: 8.0 / 13.9 / 19.7 | about +0.1% | same class as 3 | v2 after 3 |
| 3c | Flash QPI plus continuous | R12 to R8: 8.0 / 12.7 / 18.1 | about +0.1% | diminishing | v2 optional |
| 4 | Meter: instructions retired per VGA frame, latched at vsync, shown on the digits, readable at 0xFF0C | 0 CPI; makes every feature visible (CPI 1 shows 0xCB84, CPI 8 0x1970, CPI 16 0x0CB8, CPI 41 0x04F7) | about +1.5% | none | v2 must; v1 if it fits (replaces CYCLES and RETIRED) |
| 5 | ROM macro demo program (OpenRAM ROM compiler via TinyTapeout/sky130-rom-experiments; integration per smunaut/tt08-rom-test; tested as tt_um_tnt_rom_nolvt_test on ttsky25a); 64 or 128 instructions; BOOT_ROM strap kept | ROM code 1.0 with forwarding vs 1.6 to 1.8 without; loads from ROM code about 7 on the load-heavy mix; the only feature that reaches "no stalled cycles" | 64 x 32 about 3% all in; 128 x 32 about 5.5%; 256 x 32 about 10% | toolchain uninvestigated; hard-macro integration in LibreLane 3.0.3 and precheck; contents frozen at tapeout (run the same program from flash on v1 silicon first) | v2 headline if the dry run passes |
| 6 | 1-entry branch-target cache | F8 R12: 14.7 to 13.1 (-11%), 21.1 to 20.3 | about 3% | low | v2 only if the total stays at or under 74%; first to cut |
| 7 | Emulator data channel with 1-bit-per-colour VGA | loads 22 to 30 cycles; at F8 about 8.0 / 12.4 / 13-15 | about +2% net | RP2040-only firmware, not ported to the RP2350 DBv3 (GPIOBASE 16 needed for uo_out on GPIO 33-40); the demo depends on custom firmware; the VGA ladder's low bits must be disconnected | v2 optional, last, only after the board-side port is proven; the demo program needs no loads |
| 8 | Latch loop buffer | loops of at most 4 (or 8) replay at about 1 to 1.8 CPI | 6% (4) or 12% (8) plus tags | latch timing and the hand-instantiated gate | park |
| 9 | tnt rf_top register-file macro | 0 CPI | net about -2% (replaces the 27.6% flop file with 21.7% plus halo) | license; second hard macro; posedge write needs a WB-to-ID bypass | park |
| 10 | LDM/STM | 36 to 40% cheaper per word on block transfers | about +1.5 to 2% | decode and test surface | park |
| 11 | Thumb | F4, 6.25 MIPS | expander about 3 to 4% | scope change | park; note for the process post |

Best combination: 1 + 2 + 3 + 3b + 4 + 5: flash programs 8.0 / 13.9 / 19.7, ROM programs 1.0.

## Configurations

A, streamed and fast: drain, continuous read, PSRAM QPI, SCK 1:1 with SAFE, meter, full VGA, UART; about
73.2% (72.4% with a fixed UART divisor and no colour registers); CPI 8.0 / 13.9 / 19.7; SAFE gives v1's
16.0 / 33.5 / 47.5. Pins: uio and uo unchanged; ui[0] FWD_EN, [1] DISP0, [2] DISP1, [3] UART_RX, [4] DLY0,
[5] DLY1, [6] SAFE, [7] BOOT_ROM (straps latched at reset).

B, ROM demo (recommended): A plus the ROM macro at 64 instructions, UART transmit only with a fixed
divisor, no colour registers; about 74.4% (73.4% with no UART; 76.9% at 128 instructions). ROM programs 1.0
with forwarding or 1.6 to 1.8 without, about 7 on the load-heavy mix. The demo: the ROM's reset code runs a
counting kernel with an 8-deep RAW chain; the meter shows the CPI; FWD_EN flips it between 1.0 and 1.8; the
boot switch jumps to the flash program and the meter drops to 8; SAFE drops it to 16. Four switches, four
numbers, no computer. It degrades to A if the ROM never lands.

C, Harvard on pins: A plus the emulator channel, PSRAM paths removed, 1-bit-per-colour VGA, UART on its own
pin; about 74.9%; about 8.0 / 12.4 / 13-15; not recommended (firmware, demo dependency, no loads in the demo).

## Verify first, in order

1. Rewrite the controller and synthesize flattened; if the 5% does not appear only features 1 to 4 fit; take
   v1's hardening metrics as the calibration of the x1.487 factor.
2. A dry hardening of a 30-line test tile with the ICG-forwarded clock, negedge-launched data, strappable
   capture, and a create_generated_clock on the port; inspect CTS, hold on the half-cycle paths, the output
   delay report; a cocotb bench sweeping the round trip 10 to 35 ns. If it fails, switch to DTR or 50 MHz core.
3. Generate 64x32 and 128x32 ROMs with a dummy hex, integrate per smunaut/tt08-rom-test into a dummy 2x2,
   harden; record footprint with halo, DRC/LVS/precheck, whether the access is clocked, the license.
4. Flash and PSRAM models with continuous read, QPI, FFh and F5h exits; a warm-reset test.
5. A cycle-accuracy regression: the three mixes as synthetic programs on the RTL, compared with the model,
   read through the meter.
6. Measure the BTC in place; keep only at or under 74%.
7. Port pio-ram-emulator to the RP2350 and loopback-test before any RTL.
8. Run the ROM program from flash on v1 silicon before freezing it.

## For v0.2 now

Fold in: the drain policy in section 3.2 (valid/ready fetch, bubble on no valid, freeze only for a
hazard or a data access in flight, a taken branch flushes IF/ID and ID/EX and restarts); the controller
around an sck_tick with the ratio as a parameter and the integer sampling strap (zero area; do not implement
1:1, continuous read or QPI now); section 13 with the model's numbers as the expectation; a sentence that
FWD_EN has no visible effect on flash programs and only the ROM shows it (keep the ROM over the counters;
a 15-instruction program with an 8-deep dependent chain makes the on-screen count rate change about 2x with
FWD_EN); if the counters fit, implement them as the meter. Park everything else.

Sources: TinyTapeout/sky130-rom-experiments; smunaut/tt08-rom-test; tt_um_tnt_rom_nolvt_test (ttsky25a);
toivoh/pio-ram-emulator and its ttihp25a example.
