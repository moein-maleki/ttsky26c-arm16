# Measurements for the cache question, 2026-09-05

## Direct-mapped flop instruction cache on sky130_fd_sc_hd (rtl/icache_dm.v, scripts/sweep_icache_sky130.sh)

One 32-bit instruction per line, tag = 16 - log2(lines) - 2 bits, valid bit. Flattened, tt_025C_1v80.

| lines | instructions | cells | flops | synth um^2 | placed est. (x1.487) | share of the 2x2 tile (72,565 um^2) |
|---|---|---|---|---|---|---|
| 4 | 4 | 305 | 180 | 6,875 | 10,224 | 14.1% |
| 8 | 8 | 562 | 352 | 13,465 | 20,023 | 27.6% |
| 16 | 16 | 1,035 | 688 | 26,056 | 38,746 | 53.4% |
| 32 | 32 | 2,261 | 1,344 | 50,995 | 75,830 | 104.5% |
| 64 | 64 | 4,340 | 2,624 | 99,532 | 148,004 | 204.0% |

The user's 256 x 16 bits = 128 instructions is the 128-line row, about four times the tile.

## arm16 streaming variant on IHP sg13g2_stdcell, typ 1.20 V 25 C (evidence/arm16_streaming_sg13g2_typ.log)

4,176 cells, 642 flops, 65,780 um^2 synthesis area. The same RTL on sky130_fd_sc_hd is 3,517 cells and
32,698 um^2, so SG13G2 standard-cell area is 2.01x sky130 for this design.
