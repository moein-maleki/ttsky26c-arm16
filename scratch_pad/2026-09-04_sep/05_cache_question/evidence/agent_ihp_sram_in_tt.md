# Agent report: SG13G2 SRAM macros inside a Tiny Tapeout IHP project (2026-09-05)

Sources: IHP-Open-PDK HEAD 5e6d592 (2026-09-01) libs.ref/sg13g2_sram; tinytapeout.com/specs/memory; tt-support-tools
(tech/ihp-sg13g2/tile_sizes.yaml, precheck); tt-gds-action@ttihp26b; tt-multiplexer; urish/ttihp-sram-test;
EzraWolf/TinyMOA-IHP26a; splinedrive/kianv-sv32-tt-linux-soc; shuttle repos ttihp0p2/25a/26a and ttsky25b metrics;
LibreLane 3.0.5 pdk_hashes; ciel README; app.tinytapeout.com/api/shuttles/ttihp26b.

## Macros (single-port RM_IHPSG13_1P_*), LEF SIZE, lib area, clk-to-Q of A_DOUT typ/slow

| Macro | words x bits | bits | W x H (um) | area um^2 | clk-to-Q typ / slow ns |
|---|---|---|---|---|---|
| 64x16_c2 | 64x16 | 1,024 | 236.80 x 64.36 | 15,240 | - |
| 64x64_c2_bm_bist | 64x64 | 4,096 | 784.48 x 64.36 | 50,489 | 3.07 / 5.15 |
| 256x8_c3_bm_bist | 256x8 | 2,048 | 236.80 x 74.10 | 17,547 | - |
| 256x16_c2_bm_bist | 256x16 | 4,096 | 236.80 x 118.78 | 28,127 | 2.98 / 4.99 |
| 256x32_c2_bm_bist | 256x32 | 8,192 | 416.64 x 118.78 | 49,488 | - |
| 256x48_c2_bm_bist | 256x48 | 12,288 | 596.48 x 118.78 | 70,850 | 3.12 / 5.26 |
| 256x64_c2_bm_bist | 256x64 | 16,384 | 784.48 x 118.78 | 93,181 | 3.07 / 5.15 |
| 512x8_c3_bm_bist | 512x8 | 4,096 | 236.80 x 110.38 | 26,138 | - |
| 512x16_c2_bm_bist | 512x16 | 8,192 | 236.80 x 191.34 | 45,309 | 3.73 / 6.25 |
| 512x32_c2_bm_bist | 512x32 | 16,384 | 416.64 x 191.34 | 79,720 | - |
| 512x64_c2_bm_bist | 512x64 | 32,768 | 784.48 x 191.34 | 150,102 | 3.83 / 6.42 |
| 1024x8_c2_bm_bist | 1024x8 | 8,192 | 146.88 x 336.46 | 49,419 | 4.22 / 7.05 |
| 1024x16_c2_bm_bist | 1024x16 | 16,384 | 236.80 x 336.46 | 79,674 | - |

Plus larger 1P macros up to 8192x32 and ten dual-port 2P macros. Each ships cdl, doc, gds, lef, verilog and
three libs (fast 1.32 V -55 C, typ 1.20 V 25 C, slow 1.08 V 125 C). "This 1-port macro has a one-cycle
data-access." VDD 1.08-1.32 V. Setup on A_ADDR up to 0.82 ns typ, 1.27 ns slow. No maximum clock frequency
documented. Ports A_CLK, A_MEN, A_WEN, A_REN, A_ADDR, A_DIN, A_BM, A_DOUT, A_DLY plus A_BIST_*; power VDD!,
VSS!, VDDARRAY!. "Input port *_DLY must always be tied to '1'."

## Tiny Tapeout rules (tinytapeout.com/specs/memory)

"IHP has several variations of SRAM macros which can be used in shuttles which they will manufacture ...
One of these macros, 1024x8, has been successfully taped out and tested to be working." "Integrating the IHP
SRAM macro at this stage is not trivial. There have been many changes since the example project linked above,
and additional changes will come after TTIHP26A. The table below should be used as rough guidance only."
Minimum tile / area consumption (* = rotate 90 degrees): 256x8 1x2* 27.7%; 512x8 1x2* 41.2%; 1024x8 2x1* 76.0%;
256x16 1x2* 44.4%; 512x16 1x2* 71.5%; 1024x16 2x2* 60.5%; 256x32 3x4 10.9%; 256x48 3x1 71.8%; 256x64 4x1
70.4%; 512x64 4x2 56.0%. 64x64 is not in the table. No documented one-macro or minimum-tile rule.

Project mechanics (urish/ttihp-sram-test, copied by TinyMOA and KianV): macro gds/lef/lib/cdl under
`macro/<name>/`, Verilog model in `src/`; `src/config.json` MACROS block with instance location and R90
orientation, lib corners nom/min/max; PDN_MACRO_CONNECTIONS tying VDD! and VDDARRAY! to VPWR/VGND; a
`pdn_cfg.tcl` adding a Metal4 to TopMetal1 connection; MAGIC_MACRO_STD_CELL_SOURCE PDK; ERROR_ON_MAGIC_DRC
false; MAGIC_EXT_ABSTRACT_CELLS for RM_IHPSG13_.*; RTL ties A_DLY = 1, A_BIST_* = 0, A_MEN = rst_n. The shuttle
copy of the SRAM test carries a remove_empty_cells.py step. Accepted IHP tile sizes: 1x1, 1x2, 2x1, 2x2, 3x1,
3x2, 3x4, 4x1, 4x2, 4x4, 5x4, 6x1, 6x2, 6x4, 8x1, 8x2, 8x4 (the template's "167x108 uM" text is stale sky130).

## Tile geometry and density

IHP 1x1 = 202.08 x 154.98 um = 31,318 um^2; 2x2 = 419.52 x 313.74 um, core 129,036 um^2; 3x2 = 636.96 x
313.74, core 193,261; 4x1 = 854.40 x 154.98; 4x2 = 854.40 x 313.74. sky130 1x1 = 161.00 x 111.52 = 17,955;
2x2 = 75,603. Tile area ratio 1.744. Cell ratios (typ libs): inv 1.45x, nand2 1.93x, mux2 1.61x, xor2 1.66x,
DFF 2.63x. arm16 streaming variant: 32,698 um^2 sky130 vs 65,780 um^2 sg13g2 (4,176 cells, 642 flops), 2.01x.
TinyQV 3x2 on both: IHP 11,485 cells, 175,552 um^2, 90.8% util; sky130 8,770 cells, 80,436 um^2, 72.5%;
2.18x. An IHP tile carries about 0.80 to 0.87x the logic of a sky130 tile. ttihp0p2 TinyQV 2x2 closed at 95.1%.

## Fit arithmetic (10 um halo assumed; logic 65,780 um^2 synthesis, x1.2 placement growth assumed)

| Macro | 2x2 | 3x2 | 4x1 | 4x2 |
|---|---|---|---|---|
| 64x64 (784 x 64) | does not fit physically | no | fits; 53% + CPU = 104% | 26% + CPU = 52-57% |
| 256x16 (4 kbit) | 27.6% + CPU = 78.6% synth / 88.8% x1.2 | 18.4% + CPU = 52.5 / 59.3% | 79 / 90% | 39 / 44% |
| 256x64 (16 kbit) | no | no | 139% | 43% + CPU = 68 / 74% |
| 512x16 (8 kbit) | 42% + CPU = 93 / 103% | 28% + CPU = 62 / 69% | no | 46 / 51% |

## Prior art on ttihp shuttles (148 project configs swept)

| Shuttle | Project | Author | Tiles | Macro | Use | Silicon |
|---|---|---|---|---|---|---|
| ttihp0p2 | SRAM (1024x8) test | Uri Shaked | 2x2 | 1P_1024x8 R90 | byte-wide RAM test | works |
| ttihp26a | KianV SV32 TT Linux SoC | Hirosh Dabui, Uri Shaked | 8x4 | 2 x 1P_512x64 | icache + dcache, direct-mapped, 512 sets; 81,169 instances, macros 300,205 um^2, 88.9% | chips due 2027-02-28 |
| ttihp26a | TinyMOA | Ezra Wolf | 8x2 | 2P_512x32 | tightly-coupled memory | chips due 2027-02-28 |

Atari 2600 (6x2) and SIC-1 (4x2) use custom macros, not SRAM. TinyQV on IHP uses no SRAM macro.

## ttihp26b (API 2026-09-05)

deadline 2026-09-21T20:00Z; pcbs 79 of 100; tiles 0 of 240 available. Launched 2026-07-27; foundry run
IHP-2609; chips 2027-06-25; delivery 2027-08-16. Same demo board (tt-etr-dbv3, RP2350) with a different
breakout (breakout-ihp-qfn). The QSPI Pmod is silicon-proven on TTIHP25A and TTIHP0P2 (TinyQV).

## Local hardening on IHP

ciel ships ihp-sg13g2 with sg13g2_sram. LibreLane 3.0.5 pins ihp-sg13g2 c4b8b4e (2026-01-16), which
predates SRAM fixes 994d7f6 (2026-01-28, top-level gds/lef) and 21d66b4 (2026-08-12, prBoundary); the
256x16 gds and verilog differ between the pin and HEAD, lef and lib do not. tt-gds-action@ttihp26b runs
`tt_tool.py --create-user-config --ihp` and `--harden --ihp`, corner nom_typ_1p20V_25C, RT_MAX_LAYER
TopMetal1, CLOCK_PERIOD 20 ns default; macros pass through config_merged.json. IHP has no set-plus-reset DFF.
