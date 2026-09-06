# Agent report: Tiny Tapeout QSPI Flash + PSRAM Pmod spec sheet

> Research agent output, 2026-09-04, from the Pmod repo (v2.2 BOM and schematic), the TT memory and pinout
> specs, the Winbond W25Q128JV and AP Memory APS6404L-3SQR datasheets, and TinyQV's `qspi_ctrl.v`.
> Kept as evidence. Datasheet text was cached by the agent in the volatile session scratchpad only.

## 1. Identification

| Field | Value |
|---|---|
| Name | QSPI Pmod (TT docs: "QSPI Flash and PSRAM") |
| Designers | mole99 (Leo Moser) and Mike Bell |
| Repo | github.com/mole99/qspi-pmod, Apache-2.0 |
| Current board rev | v2.2 (KiCad 9.0.3, released 2025-09-19); prior v2.0, v2.1 |
| Store | store.tinytapeout.com/products/QSPI-Pmod-p716541602 |

Functional change between revisions: v2.2 changed the CS pull-ups from 1k to 10k. A second, different QSPI
Pmod exists (KianV, splinedrive, 8 MB + 8 MB) in awesome-tinytapeout-pmods; the mole99 board is the one TT
sells and documents.

## 2. Parts (v2.2 release `bom.csv`)

| Ref | Part | Qty | Capacity | Package |
|---|---|---|---|---|
| U1 | W25Q128JVSIM (Winbond) | 1 | 128 Mbit = 16 MB flash | SOIC-8 208-mil |
| U2, U3 | APS6404L-3SQR-SN (AP Memory) | 2 | 64 Mbit = 8 MB each | SOP-8 150-mil |
| R1-R3 | 10k | 3 | CS pull-ups | 0402 |
| C7 | 22 pF | 1 | optional SCK load (J2 pins 7-8) | 0402 |

Supply 3.3 V from Pmod pins 6 and 12. The `-IM` flash suffix is the DTR/QPI-capable part with QE factory 0.

## 3. Pin mapping

| Pmod signal | J1 pin | ASIC | Function | Flash pin | PSRAM A | PSRAM B |
|---|---|---|---|---|---|---|
| PMOD1 | 1 | uio[0] | CS0 flash | 1 /CS | - | - |
| PMOD2 | 2 | uio[1] | SD0 / IO0 | 5 DI | 5 SI | 5 SI |
| PMOD3 | 3 | uio[2] | SD1 / IO1 | 2 DO | 2 SO | 2 SO |
| PMOD4 | 4 | uio[3] | SCK | 6 CLK | 6 CLK | 6 CLK |
| - | 5, 11 | - | GND | 4 | 4 | 4 |
| - | 6, 12 | - | +3.3 V | 8 | 8 | 8 |
| PMOD5 | 7 | uio[4] | SD2 / IO2 | 3 /WP | 3 SIO2 | 3 SIO2 |
| PMOD6 | 8 | uio[5] | SD3 / IO3 | 7 /HOLD | 7 SIO3 | 7 SIO3 |
| PMOD7 | 9 | uio[6] | CS1 RAM A | - | 1 CE# | - |
| PMOD8 | 10 | uio[7] | CS2 RAM B | - | - | 1 CE# |

Three independent active-low CS lines; SCK and SD[3:0] hard-wired in parallel to all three chips; one device
asserted at a time. Each CS has a 10k pull-up and a cuttable trace; a cut CS frees its uio pin at header J2.

## 4. Maximum clock rates (datasheets, 3.3 V)

| Device | Mode / instruction | Max SCK |
|---|---|---|
| Flash W25Q128JVSIM | Read Data 03h | 50 MHz |
| | all other SPI/Dual/Quad reads at 3.0-3.6 V (0Bh, 6Bh, EBh) | 133 MHz |
| | DTR instructions | 66 MHz |
| | QPI mode, dummy = 2 (power-on default) | 50 MHz |
| | QPI, dummy = 4 / 6 / 8 | 80 / 104 / 133 MHz |
| PSRAM APS6404L-3SQR-SN | 03h Read | 33 MHz |
| | 0Bh Fast Read, QPI | 66 MHz |
| | EBh / 0Bh-SPI / 02h / 38h, wrap-32, VDD 3.3 V +-10% | 109 MHz |
| | linear burst crossing a 1 KB page boundary | 84 MHz |

Notes: PSRAM system max CL 15 pF; flash AC measured at CL 30 pF. PSRAM VIH min = VDD - 0.4 V (2.9 V at
3.3 V), VIL max 0.4 V, so drivers must swing rail to rail. Both devices launch read data on the falling SCK
edge (flash tCLQV <= 6 ns; PSRAM tACLK 2-5.5 ns); sample on the rising edge; SPI mode 0. PSRAM tCPH >= 18 ns
CE# high between bursts; tPU >= 150 us with a reset required. Flash tSHSL1 >= 10 ns.

## 5. Cycle counts per transaction (SCK cycles; quad = 4 bits per cycle)

| Device | Mode | Transaction | Opcode | Cmd | Addr | M7-0 | Dummy | Pre-data | Cycles/byte |
|---|---|---|---|---|---|---|---|---|---|
| Flash | SPI | Read Data | 03h | 8 | 24 | - | 0 | 32 | 8 |
| Flash | SPI | Fast Read Quad Output | 6Bh | 8 | 24 | - | 8 | 40 | 2 |
| Flash | SPI | Fast Read Quad I/O | EBh | 8 | 6 | 2 | 4 | 20 | 2 |
| Flash | SPI | EBh continuous read (M5:4 = 10 armed) | none | 0 | 6 | 2 | 4 | 12 | 2 |
| Flash | QPI | Fast Read Quad I/O | EBh | 2 | 6 | in dummy | D | 8 + D | 2 |
| Flash | QPI | EBh continuous read | none | 0 | 6 | - | D | 6 + D | 2 |
| PSRAM | SPI | Fast Read Quad | EBh | 8 | 6 | - | 6 | 20 | 2 |
| PSRAM | SPI | Quad Write | 38h | 8 | 6 | - | 0 | 14 | 2 |
| PSRAM | SPI | Enter Quad Mode | 35h | 8 | - | - | - | 8 | - |
| PSRAM | QPI | Fast Read | 0Bh | 2 | 6 | - | 4 | 12 | 2 |
| PSRAM | QPI | Fast Read Quad | EBh | 2 | 6 | - | 6 | 14 | 2 |
| PSRAM | QPI | Write | 02h or 38h | 2 | 6 | - | 0 | 8 | 2 |

D = flash QPI dummy clocks (2 default, 4, 6, 8 via C0h Set Read Parameters).

Continuous read / XIP: flash only. Arm with M5:4 = 10 (TinyQV uses M7:0 = A0h) during an EBh; the next EBh
after CS toggles skips the opcode: 12 pre-data cycles in SPI, 6 + D in QPI. Exit by shifting FFh on IO0.
The mode is volatile and does not survive a power cycle. The PSRAM has no command-skipping mode; it has
linear burst (default, crosses 1 KB pages at up to 84 MHz) or 32-byte wrap.

## 6. PSRAM write and tCEM

Quad write 38h: SPI 8 + 6 + 0 dummy; QPI 02h/38h: 2 + 6 + 0. tCEM (CE# low) max = 8 us for the standard grade
(-SN, -40 to +85 C). Datasheet 8.6: all reads and writes must be completed by raising CE# high; not doing so
blocks internal refresh and causes memory failure. tCPH >= 18 ns between bursts.

Max bytes per CE#-low window (8 us x fSCK, minus preamble, / 2 cycles per byte):

| fSCK | cycles per 8 us | QPI EBh read (14 pre) | QPI 0Bh read (12 pre) | QPI write (8 pre) |
|---|---|---|---|---|
| 10 MHz | 80 | 33 B | 34 B | 36 B |
| 12.5 MHz | 100 | 43 B | 44 B | 46 B |
| 20 MHz | 160 | 73 B | 74 B | 76 B |
| 25 MHz | 200 | 93 B | 94 B | 96 B |

Budget about 20% margin. The flash has no equivalent limit; CS may stay low indefinitely.

## 7. Purchasing

TT store, 20.00 EUR, "In stock: 39 available" on 2026-09-04, shipped assembled. Gerbers, BOM and positions
published with each GitHub release (JLCPCB-ready), Apache-2.0.

## 8. Reference Verilog

MichaelBell/tinyQV `cpu/qspi_ctrl.v` (Apache-2.0): "A QSPI controller for the QSPI PMOD". Companion
`cpu/qspi_flash.v`, cocotb tests `test/test_qspi_ctrl.py`, SymbiYosys proof `verify/qspi_ctrl.sby`.
Interface: 25-bit address (0x0000000-0x0FFFFFF flash, 0x1000000-0x17FFFFF RAM A, 0x1800000-0x1FFFFFF RAM B),
byte streaming with start_read/start_write, data_ready/data_req, stall_txn, stop_txn. It assumes the PSRAMs
are already in QPI mode and the flash already in EBh continuous read mode; uses 0Bh for PSRAM reads and 02h
for writes; drives M7:4 = 1010 to keep continuous read armed; enforces 2 cycles before reselecting the same
RAM for tCPH.

Source comment: "Round trip latency of the TT mux is a little over 20ns, so we need configurable delay cycles
for reads to reach faster clock speeds." Latency configured 1-3 half-SPI-clock steps via spi_data_in[2:0]
during reset. On ttsky25a silicon: 64 MHz core / 32 MHz QSPI works at latency 1 and 2.

## 9. Flags

1. Flash variant: BOM, KiCad value and store marking say W25Q128JVSIM (QE factory 0, QPI/DTR capable);
   TinyQV's README says W25Q128JVSIQ (QE factory 1, no QPI/DTR). Resolve in silicon: 9Fh returns EF 70 18
   for -IM, EF 40 18 for -IQ; then read SR-2 (35h) bit 1.
2. Pull-ups: README says 1k, v2.2 schematic and BOM say 10k.
3. PSRAM numbers from APS6404L-3SQR Rev 2.1 (2019-10-25); the schematic links Rev 2.3.
4. Winbond AC note 6 "4-bytes address alignment for QPI/Quad Read" is contradicted by RP2040 XIP practice.
5. The ">20 ns TT mux round trip" is a source comment, not a published TT spec.
6. tCEM grade mapping (-SN, standard, 8 us) is inferred from the ordering table.

## 10. Implications for a 20-25 MHz arm16

- All 8 uio consumed; uio[1], [2], [4], [5] must be true bidirectional with per-pin OE.
- Neither device's frequency ceiling binds at 20-25 MHz. The binding constraint is round-trip latency:
  about 20 ns mux + 6 ns flash tCLQV = 26 ns plus setup against a 40-50 ns period. One-cycle read latency
  should close; make it configurable (1-3 half-cycles) as TinyQV does. (Derived, not measured.)
- Bring-up in single SPI first: drive uio[4] and uio[5] HIGH during all pre-QE commands (with QE = 0 they
  are /WP and /HOLD with no board pull-up). Then 06h, 31h with S9 = 1 to set QE (non-volatile, once), 35h to
  each PSRAM to enter QPI (volatile, every power-up), then quad traffic.
- Continuous read mode is volatile. TinyQV depends on the host leaving the flash armed. A host-free chip
  must issue the full 20-cycle EBh after reset and arm continuous read itself.
- A host is still needed once to program the flash. tinytapeout-flasher does this over the demo board's RP2
  via single SPI at 10 MHz on uio[0..3] (9Fh, 06h, 20h, 02h, 03h); it does not set QE or continuous mode.
- Per 32-bit instruction from flash: 20 SCK cycles per fetch in continuous read with CS toggled; 8 cycles
  when CS is held and the address is sequential. Consider a small prefetch buffer to amortize the preamble.

Sources: tinytapeout.com/specs/memory, tinytapeout.com/specs/pinouts, github.com/mole99/qspi-pmod,
awesome-tinytapeout-pmods, the store page, github.com/MichaelBell/tinyQV, the ttsky25a TinyQV chip page,
tinytapeout-flasher, W25Q128JV Rev H and W25Q128JV-DTR Rev B datasheets, APS6404L-3SQR Rev 2.1 datasheet.
