# Agent report: dense on-chip storage on sky130 at Tiny Tapeout (2026-09-06)

Tile geometry (tt-support-tools tech/sky130A/tile_sizes.yaml): 1x1 161.00 x 111.52 = 17,955 um^2; 1x2 36,347;
2x2 334.88 x 225.76 = 75,600 um^2 die (72,565 core after margins).

| Option | Measured density | Bytes per 1x1 | Maturity | Integration |
|---|---|---|---|---|
| ROM, tnt/OpenRAM macro | 24,576 bits in 144.9 x 112.3 um = 1.51 bits/um^2 | about 3.4 kB | silicon-proven ttsky25a ("read all the ROM successfully with 10 ns propagation time") | hard macro via LibreLane MACROS |
| tnt rf_top register file | 1,024 bits in 132.64 x 118.70 um = 15,744 um^2 = 0.0650 bits/um^2 | about 146 B | silicon-proven via FemtoRV on ttsky25b | hard macro, custom cells inside |
| C4M full-custom SPSRAM | 1,024 bits in one 1x1 | 128 B, 66 MHz | submitted ttsky26a, silicon not back | full-custom GDS |
| Latch RAM (inferred latches) | 512 bits in 1x1 at PL_TARGET_DENSITY 0.88 = 0.0285 bits/um^2 | 64 B | silicon-proven TT06 | RTL plus explicit sky130 cells |
| DFF RAM (plain RTL) | about 320 DFFs per tile = 0.0178 bits/um^2 | 40 B | proven | RTL |
| DFFRAM RAM32 | 1,024 bits in 401 x 136 um = 0.0188 bits/um^2 | 128 B, needs 3x2 | proven TT05 | macro |
| OpenRAM foundry SRAM | 8 kbit in 479.78 x 397.5 um = 0.0430 bits/um^2 | too tall for any TT tile | not usable at TT on sky130 | - |

## tt_um_tnt_rf_validation (ttsky25b, Sylvain Munaut)

A 1x2 harness; the datasheet: "an optimized SRAM macro organized as 32 words of 32 bits", "three access
ports: one write port and two read ports", "designed for TinyTapeout especially", "compact enough (~88% of
the area of a single tile)", "doesn't use any DRC waiver/special rules"; LFSR generators and capture/compare
on independent clocks measure setup, hold, clock-to-out and retain. The GDS contains custom cells
(rf_bit_cell, rf_bit_array, rf_bl_write, rf_bl_read, rf_wldrv, rf_adec_ckt x325, rf_adec_dyn, rf_ctrl,
drivers, rf_sc_input/output) plus sky130 dlxtp_1, dlxtn_1 latch pairs as output registers, inv_4, buf_4,
taps, decap, fill. LEF: MACRO rf_top CLASS BLOCK SIZE 132.640 BY 118.700: 15,744.4 um^2 for 1,024 bits.
Does not fit a 1x1 (118.70 > 111.52). Its own validation results are unpublished ("no test procedure has been
written yet"); FemtoRV on ttsky25b uses it and its author reports "Seems to work perfectly ... ran it at
80 MHz". Reuse: MichaelBell/ttsky25b-femtorv-soc (Apache-2.0) ships macro/rf_top.gds.gz, .lef, .lib
(library sky130_s47_lib, cell rf_top) and src/rf_top.v; config.json: MACROS instance at [0.1, 45.0]
orientation E, PDN_MACRO_CONNECTIONS "i_femtorv.i_rf VPWR VGND VDPWR VGND", FP_PDN_HORIZONTAL_LAYER met3,
FP_MACRO_HORIZONTAL_HALO 3, FP_MACRO_VERTICAL_HALO 0, FP_PDN_VOFFSET 10, ERROR_ON_PDN_VIOLATIONS 0,
MAGIC_NO_EXT_UNIQUE 1, RUN_IRDROP_REPORT 0 ("All met4 stripes are not connected internally"). License:
smunaut/ttsky25b-rf-validation and ttsky25a-rf-test carry no LICENSE; ask tnt.

## tt_um_urish_sram_poc

TT03p5, "SRAM Controller PoC (128 bytes)", 1x1: a controller pinned out to an OpenRAM macro
sky130_sram_2kbyte_1rw1r_32x512_8 outside the tile (683.1 x 416.54 um, about 16 tiles); 32 of 512 words
addressed. No published conclusion. Not a dense cell.

## MichaelBell/tt06-memory (latch RAM, silicon-proven)

"64 byte RAM built out of latches", 512 latches, 1x1; TT's "512 bits per tile" figure is the OpenLane setting
PL_TARGET_DENSITY 0.88. Latches inferred by a level-sensitive always block; the gating AND
(sky130_fd_sc_hd__and2_1), read tri-states (ebufn_4) and output buffer (clkbuf_4) instantiated explicitly
under `ifdef SIM, with SYNTH_READ_BLACKBOX_LIB 1 and RSZ_DONT_TOUCH_RX "lm_dt_". Two-cycle write with a
half-cycle gate pulse from a negedge-triggered flop; reads through four 16:1 muxes and tri-states. Rules:
no consecutive writes; reset does not clear the RAM. Silicon: "tweaked tests confirm the 64 byte RAM works".

## Others

tt_um_c4m_spsram_direct (ttsky26a, Full Custom): 128 x 8 in a 1x1 at 66 MHz, silicon not back.
ccattuto/tt08-sr-latch: 512-bit latch shift register in one tile (shift only). tt06-256-bits-dff-mem: 256
bits in a 1x1 at density 0.8. DFFRAM RAM32: 128 B, 401 x 136 um, 3x2 tiles at 54%; smallest config 32 words.
ROM: urish/tt-rom-vga-screensaver rom_vga_logo.lef SIZE 144.9 x 112.3 holding 24,576 bits; tnt tt09-rom-test
packs rom_32k_core plus two rom_4k in a 1x2. Custom-GDS paths: whole-project (language Analog, prebuilt gds
and lef, met1 to met4 only, pins on met4 where the template DEF puts them) or a digital project embedding a
macro via MACROS (the path used here).

## sky130_fd_sc_hd storage cell areas (all 2.72 um tall)

dlxtp_1 15.0144; dlxtn_1 15.0144; dlrtp_1 16.2656; dlclkp_1 17.5168; dlxbp_1 18.768; dfxtp_1 20.0192;
dfxbp_1 23.7728; dfrtp_1 25.024; sdfxtp_1 26.2752; edfxtp_1 30.0288. Latch to flop 0.75; to the reset flop 0.60.

## Latches in LibreLane

OpenLane issue 40 (latches not mapped) is closed; LibreLane reports latches after proc and maps them with
dfflibmap; the dlxtp_1 liberty has setup_falling, hold_falling, min_pulse_width arcs. OpenSTA's time-borrowing
model makes latch-path setup slack pessimistic, so practical designs constrain the gate so it never borrows.
TT has no latch-specific guidance beyond pointing at Bell's project.

Sources: tinytapeout.com/chips/ttsky25b/tt_um_tnt_rf_validation; smunaut/ttsky25b-rf-validation;
MichaelBell/ttsky25b-femtorv-soc; MichaelBell/tt06-memory; tinytapeout.com/specs/memory; /specs/analog;
/chips/silicon-proven; TinyTapeout/tt03p5-sram-poc; ccattuto/tt08-sr-latch; TinyTapeout/tt06-256-bits-dff-mem;
tt06-dffram-example; Cloud-V/DFFRAM; tt_um_c4m_spsram_direct; urish/tt-rom-vga-screensaver;
tt_um_tnt_rom_nolvt_test; ttsky-analog-template; OpenLane issue 40; sky130_fd_sc_hd dlxtp docs.
