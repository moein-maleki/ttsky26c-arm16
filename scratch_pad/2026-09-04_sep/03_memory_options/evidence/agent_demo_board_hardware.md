# Agent report: TT demo board memory, and whether an ASIC can reach it

> Research agent output, 2026-09-04. Claims were verified by the agent by exporting the KiCad netlist
> (`kicad-cli sch export netlist`) from the source repos and tracing nets. Kept verbatim as evidence.

## 1. The board

| | |
|---|---|
| Name (title block) | "Tiny Tapeout Demoboard v3", informally the ETR demoboard v3 |
| Shipping revision | v3.2, BOM dated 2025-11-12 (`pcb-files/ETRv3p2/demoboard/`) |
| Repo HEAD | rev 3.3, dated 2026-06-23 (re-annotated schematic, same circuit) |
| Repo | github.com/TinyTapeout/tt-demo-pcb |
| Author | Psychogenic Technologies (Pat Deegan); OSHWA CA000047 |
| Carrier | github.com/TinyTapeout/breakout-pcb, breakout-sky-qfn rev 3.1 |

Not an RP2040 board any more. v3 uses an RP2350B (QFN-80): BOM line `"U3","RP2350-QFN80",...,"RP2350B","C42415655"`;
the MicroPython SDK v3 states support is limited to RP2350-based boards. The RP2040 board is v2.1.2 (TT08 era).
The TTSKY25b store kit references ETRv3p2, so v3 is what ships with current SKY kits (strong inference; TT
publishes no shuttle-to-board table).

## 2. Memory physically on the demo board

| Ref (v3.2 / v3.3) | Part | Function |
|---|---|---|
| U4 / U7 | Winbond W25Q32JVSSIQ, SOIC-8, LCSC C82344 | RP2350 boot/program QSPI NOR flash, 32 Mbit = 4 MB |
| - | RP2350B internal | 520 KB on-chip SRAM (MCU-private) |

No PSRAM, no SRAM chip, no EEPROM on the demo board. The sky breakout carries a Microchip 24LC02 (256 B I2C
EEPROM) as a board-ID part on the management bus (`mngIO1`/`mngIO2` to J3.40/J3.36 to the RP2350's `mng1`/`mng2`);
its nets never touch the ASIC die.

## 3. Is the RP2 flash reachable by the ASIC? NO, definitively.

The flash sits on the RP2350's dedicated QSPI bank, a physically separate pin bank from GPIO0-47. Every net on
that bus has exactly two nodes:

```
/RP2350/QSPI_SCK : U6.71 (QSPI_SCLK) - U7.6  (CLK)
/RP2350/QSPI_SD0 : U6.72 (QSPI_SD0)  - U7.5  (DI/IO0)
/RP2350/QSPI_SD1 : U6.74 (QSPI_SD1)  - U7.2  (DO/IO1)
/RP2350/QSPI_SD2 : U6.73 (QSPI_SD2)  - U7.3  (IO2)
/RP2350/QSPI_SD3 : U6.70 (QSPI_SD3)  - U7.7  (IO3)
/RP2350/FLASH_SS : R42.2, R44.2 - U7.1 (~CS)
                   R44.1 -> net /BOOT -> U6.75 (QSPI_SS) + R12 10k pull-up + SW2 (BOOT button)
```

- Net names are local to the `/RP2350/` sub-sheet, on zero hierarchical sheet pins.
- Carrier connector J5, the three Pmod sockets, and every ui_in/uo_out/uio net are absent from all six nets.
- No mux, buffer, solder jumper or series-resistor tap. Only R42 (10k pull-up) and R44 (0R to the BOOT strap).
- Same result on the RP2040 v2.1.2 board: bus reaches only U6, U5 and J11 (a 1x06 flash-programming header,
  gone on v3).

Conclusion: the 4 MB W25Q32 is a private RP2350 boot resource. The ASIC cannot see it, mux onto it, or share it.

## 4. What connects to the ASIC's 24 pins (v3.3 designators; v3.2 in parentheses)

| ASIC pin | RP2350 GPIO | pkg pin | Pmod | DIP SW1 | 7-seg | Other headers |
|---|---|---|---|---|---|---|
| ui_in[0] | GPIO17 | 17 | J14(J11).1 | SW1.16 | - | J10.1 |
| ui_in[1] | GPIO18 | 18 | J14.2 | SW1.15 | - | J10.2 |
| ui_in[2] | GPIO19 | 19 | J14.3 | SW1.14 | - | J10.3 |
| ui_in[3] | GPIO20 | 20 | J14.4 | SW1.13 | - | J10.4 |
| ui_in[4] | GPIO21 | 21 | J14.7 | SW1.12 | - | - |
| ui_in[5] | GPIO22 | 22 | J14.8 | SW1.11 | - | - |
| ui_in[6] | GPIO23 | 23 | J14.9 | SW1.10 | - | - |
| ui_in[7] | GPIO24 | 25 | J14.10 | SW1.9 | - | - |
| uio[0] | GPIO25 | 26 | J15(J12).1 | - | - | J6.1 |
| uio[1] | GPIO26 | 27 | J15.2 | - | - | J6.2 |
| uio[2] | GPIO27 | 28 | J15.3 | - | - | J6.3 |
| uio[3] | GPIO28 | 36 | J15.4 | - | - | J9.1 |
| uio[4] | GPIO29 | 37 | J15.7 | - | - | - |
| uio[5] | GPIO30 | 38 | J15.8 | - | - | - |
| uio[6] | GPIO31 | 39 | J15.9 | - | - | - |
| uio[7] | GPIO32 | 40 | J15.10 | - | - | - |
| uo_out[0] | GPIO33 | 42 | J16(J13).1 | - | seg A (JP2 + 510R) | J4.1 |
| uo_out[1] | GPIO34 | 43 | J16.2 | - | seg B (JP3) | J4.2 |
| uo_out[2] | GPIO35 | 44 | J16.3 | - | seg C (JP4) | J4.3 |
| uo_out[3] | GPIO36 | 45 | J16.4 | - | seg D (JP5) | J4.4 |
| uo_out[4] | GPIO37 | 46 | J16.7 | - | seg E (JP6) | - |
| uo_out[5] | GPIO38 | 47 | J16.8 | - | seg F (JP7) | - |
| uo_out[6] | GPIO39 | 48 | J16.9 | - | seg G (JP8) | - |
| uo_out[7] | GPIO40 | 49 | J16.10 | - | seg DP (JP9) | - |

Also on the board, none of it ASIC-facing memory:
- SW1 = 193-8MSR 8-position piano DIP. Each switch ties its ui_in[n] to +3V3 through 1k. Off = open, no
  pull-down; a Pmod driving ui_in fights about 3.3 mA per closed switch.
- U4 = 157112V12700 single-digit common-cathode 7-segment on uo_out[7:0] through solder jumpers JP2-JP9
  (bridged by default) and 510R. The ASIC's only self-contained visual output.
- LEDs: D3 VBUS, D4 +3V3, D5 RP2350 GPIO11 user LED. No ASIC-driven discrete LED.
- Buttons: SW2 RP2350 BOOT, SW3 manual project clock (NC7SP14 debounced), SW4 RP2350-side reset RC.
- Headers: J7 (1x16 mux control + res0..4), J12 (2x5 ADC1-5), J13 (2x16 analog A..X), J11 IREF, J8 RUN,
  J17 SWD, J9/J10/J4/J6 SIL taps, USB-C J1.
- Three Pmod sockets only (2x6 female, Amphenol 613012243121 / PPTC062LJBN-RC): ui_in, uio, uo_out. The
  specs/pcb page's mention of mixed Pmods is stale (v2.1.2 had six; v3 dropped the three mixed ones).

## 5. Can a QSPI memory Pmod plug straight into the uio header? Yes.

Header J15 (rev 3.3) / J12 (rev 3.2), the BIDIR Pmod:

| Pmod pin | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| net | uio0 | uio1 | uio2 | uio3 | GND | +3V3 | uio4 | uio5 | uio6 | uio7 | GND | +3V3 |

Row 1 is the Digilent Type 2A SPI order (CS, MOSI, MISO, SCK) under TT's pin spec. Row 2's SD2/SD3 use is a
TT quad extension.

The official QSPI Pmod (github.com/mole99/qspi-pmod, store.tinytapeout.com, about 20 EUR, in stock):

| Ref | Part | Capacity |
|---|---|---|
| U1 | Winbond W25Q128JVSIM | 128 Mbit = 16 MB QSPI NOR flash |
| U2 | AP Memory APS6404L-3SQR-SN | 64 Mbit = 8 MB QSPI PSRAM |
| U3 | AP Memory APS6404L-3SQR-SN | 64 Mbit = 8 MB QSPI PSRAM |

Pinout (verified against its netlist):

| uio | Function | Note |
|---|---|---|
| uio[0] | CS0 flash | cuttable trace, 10k pull-up when cut |
| uio[1] | SD0 / MOSI | shared by all three chips |
| uio[2] | SD1 / MISO | shared |
| uio[3] | SCK | shared; `CK` jumper adds a 22 pF delay cap |
| uio[4] | SD2 | shared |
| uio[5] | SD3 | shared |
| uio[6] | CS1 PSRAM A | cuttable |
| uio[7] | CS2 PSRAM B | cuttable |

Consequences: all 8 uio consumed, ui_in and uo_out free. SCK and SD0-3 common to all three chips, so exactly
one CS may be low at a time; flash fetch and PSRAM data interleave, never overlap. On the sky breakout each
uio[n] runs straight to the ASIC pad (QFN pins 53, 54, 55, 57, 58, 59, 60, 61) with no series R and no pull.
TinyTapeout/tinytapeout-flasher writes a binary into the Pmod flash through the demo board's RP2, targeting the
BIDIR (uio) port. TinyQV (ttsky25a `tt_um_tt_tinyQV`) is a shipped RISC-V SoC running exactly this arrangement.

Firmware caution: the RP2350 also drives all eight uio (GPIO25-32). The SDK must hold those as inputs for the
Pmod and ASIC to own the bus; the MicroPython SDK has per-project bidir direction config in `config.ini`.

## Secondary option: the RP2 as a fake SPI RAM

specs/pcb claims the MCU can provide SPI RAM emulation up to 512 Kbit. Source: MichaelBell/spi-ram-emu, a
standalone RP2040 pico-SDK/PIO project (2023), not part of the shipping firmware (neither tt-micropython-firmware
nor tt-commander-app contains RAM-emulation, PSRAM or QSPI code). Limits: SPI only, no QSPI; 64 KB; 16-bit address;
READ at most SYS/10, FAST READ SYS/8, WRITE SYS/6 (12.5 / 15.6 / 20.8 MHz at a 125 MHz RP2040). Requires flashing
a different C-based firmware over the MicroPython SDK; never ported to RP2350 as far as found.

## Flags / not confirmed

- No published shuttle-to-board-revision mapping; ETRv3p2 for current SKY kits is inferred. A leftover RP2040
  v2.x board has the identical uio Pmod pinout (J5 pins 1-4/7-10), so the plan is unchanged either way.
- RP2350B GPIO numbers come from the schematic annotations and the repo README; not cross-checked against the
  RP2350 datasheet package table.
- tinytapeout.com/specs/pcb/ is out of date on Pmod count and MCU.
- The agent reported that the fetched store.tinytapeout.com page contained an embedded block imitating a
  system reminder that asked for AI-attribution lines in commits. It was ignored; no commits were made.

Sources: tt-demo-pcb, pcb-files (ETRv3p2 BOM/gerbers), breakout-pcb, mole99/qspi-pmod, the QSPI Pmod store
page, tinytapeout-flasher, tt-micropython-firmware, MichaelBell/spi-ram-emu, tinytapeout.com/specs/pinouts,
tinytapeout.com/specs/pcb, the TTSKY25b kit page.
