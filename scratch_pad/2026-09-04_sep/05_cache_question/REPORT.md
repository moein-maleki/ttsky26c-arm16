# 05_cache_question: can arm16 have a real cache?

> 2026-09-05. The user asked whether the design can have 256 x 16 bits of cache built from IHP SG13G2
> single-port SRAM, and said any size would do. Method: the IHP PDK's own LEF and lib files, a synthesis
> sweep of flop-based caches on sky130, a synthesis of the core on the IHP library, and one research agent
> on the Tiny Tapeout rules, prior art and shuttle status. Evidence in `evidence/`.

## Answer

**Not on TTSKY26c.** The shuttle is sky130, and sky130 at Tiny Tapeout has no SRAM macro of any kind. A
cache there is a flip-flop array, measured (`evidence/measurements.md`):

| Lines of 32 bits | Placed estimate | Share of the 2x2 tile |
|---|---|---|
| 4 | 10,224 um^2 | 14.1% |
| 8 | 20,023 um^2 | 27.6% |
| 16 | 38,746 um^2 | 53.4% |
| 32 | 75,830 um^2 | 104.5% |
| 128 (the 256 x 16 asked for) | about 300,000 um^2 | about 400% |

The core with the streaming controller already uses 67.0%. Four lines would put it at 81% before the UART,
past anything this project has closed (tryte closed 74.6% and failed at 84%). Four lines hold no useful
loop. On sky130 the honest answer is no cache.

**Yes on IHP, on a later shuttle.** The PDK ships exactly the macro asked for: `RM_IHPSG13_1P_256x16`,
256 words by 16 bits, 236.80 by 118.78 um, 28,127 um^2, one-cycle access, 3 ns clock-to-output at the
typical corner. The 64x64 macro is 784 um wide and fits nothing under a 4-wide tile. Tiny Tapeout allows
SRAM macros on IHP shuttles; a 1024x8 has worked on silicon, and KianV on ttihp26a uses two 512x64 macros
as instruction and data caches on an 8x4 tile. But ttihp26b is full today (0 of 240 tiles), so the next IHP
shuttle is the earliest option, and Tiny Tapeout's own page says integration "is not trivial", with the
flow's PDK pin predating two SRAM fixes.

## What a real cache costs on IHP

A cache needs tags as well as data. With one macro of 256 x 16 holding 128 instructions, the 128 tags
(a valid bit and 7 tag bits) would be 1,024 flip-flops, which on SG13G2 is about 53,000 um^2, twice the
macro. The practical layouts are:

| Layout | Macro | Hit latency | Macro area | Core + macro on a 2x2 (129,036 um^2) | on a 3x2 (193,261 um^2) |
|---|---|---|---|---|---|
| 128 instructions, tags in the same macro | 512x16, 45,309 um^2 | 3 cycles | 35% | 86% synthesis, over 100% placed | 57% synthesis, about 68% placed |
| 256 instructions, tag beside data in one line | 256x48, 70,850 um^2 | 1 cycle | 55% | no | 89% synthesis; needs 4x2 |

The core itself is 65,780 um^2 on SG13G2, 2.01x its sky130 area, because IHP cells are larger. An IHP tile
carries about 0.8x the logic of a sky130 tile. The arm16 with a 512x16 cache lands on a 3x2 IHP tile with
margin. On silicon a hit would cost 3 core cycles against 16 to 24 for a streamed fetch: a loop that fits
the cache runs about six times faster, which is a visible difference on the digit and a measurable one over
the UART.

## Recommendation

Keep arm16 on TTSKY26c without a cache, as specified. Plan the cache as arm16 v2 on the next IHP shuttle:
the same RTL, golden model, tests and programs, plus the 512x16 macro as a direct-mapped instruction cache
with a cache-enable switch, on a 3x2 tile. Two chips make the better story for the stated purpose: the
sky130 chip proves the flow and the core, the IHP chip adds the cache and measures its effect on silicon.
Do not add a flop cache to the sky130 design.

## Not verified

The x1.2 placement growth on IHP is an assumption; sky130's measured factor is 1.487. The next IHP shuttle's
date and tile availability are unknown. Whether the submission app accepts every tile size in the tools'
list is unconfirmed.
