# Which memory for arm16: the demo board's flash, the RP2 as memory, or the QSPI Pmod

> 2026-09-04. Question from the user: which is faster as instruction and data memory for arm16, the Tiny
> Tapeout PCB's QSPI flash or an external Pmod memory, and what did other people do. Method: six research
> agents (schematic netlists, datasheets, the TinyQV source and its author's posts, the machine-readable TT
> project index for all 27 shuttles), a fetch-latency model built from the datasheet cycle counts, and two
> synthesis runs that measure what the faster protocol costs in area. Evidence in `evidence/`; commands in
> `INFRA_AND_COMMANDS.md`.

## Answer

**The board's QSPI flash is not an option.** The only flash on the Tiny Tapeout demo board is a 4 MB
W25Q32 on the RP2350's dedicated QSPI bank. Every net on that bus has exactly two nodes, the MCU pad and the
flash pin, with no mux, buffer, jumper or tap, and none of the 24 project pins appear on it. It is the MCU's
boot memory and the ASIC cannot reach it. This was proved by exporting the KiCad netlist of the shipping
board, not from prose docs (`evidence/agent_demo_board_hardware.md`).

**What the board can offer is the RP2 pretending to be a memory chip**, and the only ready-made version is
the slowest choice by a wide margin: one data line, a documented ceiling of a tenth of the MCU clock (12.5 to
15 MHz), a 400 ns dead time between accesses, custom C firmware replacing the shipped MicroPython, code
written for the RP2040 in 2023 and never ported to the RP2350 the current board carries. Its author went on
to use the QSPI Pmod for his own CPU. A faster PIO emulator exists (toivoh's, 128 KB of 16-bit words on four
pins at 22-cycle random latency) but it too is RP2040-only and would make the demo depend on firmware nobody
has written for this board.

**The QSPI Pmod is the memory.** 20 EUR at the Tiny Tapeout store, 39 in stock on 2026-09-04, assembled:
a 16 MB W25Q128JV flash and two 8 MB APS6404L PSRAMs on all eight `uio` pins. Four data lines wide, the
flash is non-volatile so the program survives power-off, which is what makes a host-free demo possible, and
it is silicon-proven on this exact board by TinyQV and about 90 other Tiny Tapeout projects. Every CPU on
the platform that executes from external memory uses it.

Two facts from the index for the process post: no ARM core has ever been taped out on Tiny Tapeout, and no
project has ever pipelined a CPU that fetches from external serial memory. arm16 would be the first on both.

## The numbers

Cycle counts per 32-bit instruction fetch from the datasheets (`fetch_latency_model.py`; SCK cycles, then
core cycles at SCK = core/2, then MIPS at a 25 MHz core):

| Memory and protocol | Per access | With command skip | Streaming, CS held |
|---|---|---|---|
| RP2 SPI-RAM emulation, one lane | 56 / 112 / 0.22 | none | 32 / 64 / 0.39 |
| Pmod flash, EBh quad I/O, SPI mode | 28 / 56 / 0.45 | 20 / 40 / 0.62 | 8 / 16 / 1.56 |
| Pmod flash, EBh, QPI mode | 18 / 36 / 0.69 | 16 / 32 / 0.78 | 8 / 16 / 1.56 |
| Pmod PSRAM, 0Bh, QPI mode | 20 / 40 / 0.62 | none | 8 / 16 / 1.56, capped by tCEM |

Streaming means chip select stays low and the clock keeps running while the address advances linearly; the
device auto-increments and the controller never re-sends an address. A taken branch or a data access breaks
the stream and pays the per-access column once. The PSRAM cannot stream for long: its refresh runs only while
chip select is high, and holding it low past 8 us causes data loss, which at 12.5 MHz caps a burst at about
10 instructions. The flash has no such limit.

Against the RP2 route at matched clocks the Pmod is 3.1x faster on a random fetch, 6.4x on raw throughput,
and 8.2x on a sequential burst (`evidence/agent_rp2_memory_server.md`).

## What decides speed is the fetch protocol, not the chip

The probe's controller re-issues command, address and dummy cycles for every instruction, which is why the
fit report estimated one instruction per 60 core cycles. Holding chip select and streaming brings a
sequential fetch to 8 SCK cycles, 16 core cycles at core/2. That is a 3.5x gain and it is worth more than
the difference between any two memories in the table. TinyQV's author calls it the whole ballgame, and the
index has a counterexample: an 8-bit processor on ttsky26a reports 100 clocks per instruction from naive
per-fetch addressing.

Measured cost of adding it (`rtl_variants/`, `evidence/synth_flat_streaming.log`):

| Variant | Cells | Flops | Synth um^2 | Placed est. | Utilization | Depth |
|---|---|---|---|---|---|---|
| 02 probe, per-access, wrong pin map | 3,403 | 616 | 31,668 | 47,090 | 64.9% | 56 |
| streaming, official pin map, 24-bit address | 3,517 | 642 | 32,698 | 48,621 | 67.0% | 57 |

Two utilization points and one gate level. Affordable.

## Clock, timing and the real ceiling

- The sky130 output pad is rated 33 MHz. People have driven this Pmod's clock at 32 MHz; TinyQV stops
  working at 35 MHz. Its author runs SCK = core/2 for that reason alone (64 MHz core, 32 MHz SCK), and
  DUMBRV's author states the rule outright: if the bus can only do 20 MHz, run the design at 40.
- The TT mux adds a measured 20 ns round trip. With the flash's 6 ns clock-to-output and about 3 ns setup
  that is 29 ns. Sampling a full SCK period after the launch edge closes at 25 MHz SCK with 11 ns to spare
  and at 12.5 MHz with 51 ns. Sampling half a period later, the naive mode-0 habit, would cap SCK at 17 MHz.
  nanoV, the only external-memory CPU that has driven the board's seven-segment digit, capped at 18 MHz for
  exactly this reason: "the design of the SPI controller, combined with the mux latency".
- At a 25 MHz core, SCK = core/2 = 12.5 MHz from a toggle flop is safe, simple, and 3.7x faster than the
  probe once streaming is in. The upgrade path, if hardening closes with margin, is to clock the chip at
  50 MHz, keep the QSPI controller at clk/2 = 25 MHz, and clock-enable the pipeline every other cycle under a
  multicycle constraint. That doubles fetch rate again with no forwarded clock.
- Neither device's own limit binds: flash 133 MHz for EBh, PSRAM 84 MHz linear burst. Board capacitance
  (three devices on the shared data lines, no series termination) makes the datasheet maxima unreachable
  anyway, and is irrelevant below 33 MHz.

## What the prior art did (TinyQV, 2x2, sky130, same Pmod, same board)

Michael Bell's TinyQV is the reference: RV32EC on a 2x2 tile, code from the flash, data in the PSRAM, one
shared bus, 64 MHz core with 32 MHz QSPI, 8 core clocks per compressed instruction, 16 per 32-bit one,
CoreMark 5.13, measured to 90 MHz on ttsky25a silicon. The techniques, in order of leverage
(`evidence/agent_tinyqv_prior_art.md`):

1. Hold chip select and keep clocking; restart only on a taken branch or a data access.
2. Stall by gating SCK low with chip select held, at instruction boundaries only.
3. Arm the flash's continuous-read mode so a restart costs 12 cycles, not 20.
4. A configurable receive-sampling delay of 1 to 3 core clocks, set from the input pins during reset, so
   the 20 ns mux latency is absorbed without slowing the clock. Two independent silicon-proven designs do
   this; it is why they work on real boards.
5. Drive SCK from the falling core edge so data leads clock by half a cycle. Launching both on the same
   edge violates the flash's setup time; that bug shipped in KianV and the Pmod's 22 pF clock cap exists as
   the hardware band-aid for it.
6. A four-entry 16-bit prefetch ring, not a cache.
7. Fetch fully decoupled from execute; early branch resolution; multi-word loads to amortize restarts.
8. Never execute from PSRAM, which removes the 8 us refresh problem entirely.
9. Keep data outputs constant when idle: toggling data through the mux next to SCK coupled enough to pull
   32 MHz clock pulses down to 2 V, and cost him weeks.
10. SDC: 65% of the period budgeted to IO delay on the QSPI pins, tighter on SCK, extra clock uncertainty
    for the mux. Copy the file.

Other comparable projects (`evidence/agent_tt_project_survey.md`): FFD16 (ttsky26a, 2x2, 25 MHz, 16-bit,
QSPI flash in continuous read plus SPI PSRAM, no internal memory, nearly this spec; note its `uio[1]` and
`uio[2]` labels are swapped against the Pmod); FazyRV-ExoTiny (2x2, arms QPI then continuous read at boot,
"an additional dff breaks convergence"); Arctic0 (1x2, 16-bit, multi-cycle, stalls the CPU clock during
SPI); the RLE Video Player (1x1, plays Bad Apple from the Pmod using plain 6Bh reads with no mode setup at
all, so it boots from a cold flash with zero host involvement); DJ8 (1x1, silicon-proven, carries a 256-byte
internal ROM so that with nothing attached a DIP switch selects a demo on the seven-segment digit); KianV
uLinux (8x2, boots Linux from the same Pmod). Reusable code: `tinyQV/cpu/qspi_flash.v`, 146 lines,
Apache-2.0, flash-only, rated by its author to about 30 MHz QSPI; add the sampling delay and negedge SCK from
`qspi_ctrl.v`.

## What a host-free demo requires

- The flash holds the program across power cycles. Loaded once with `tinytapeout-flasher` through the demo
  board over single SPI at 10 MHz. That is the only time a computer touches it.
- **Use no volatile mode at all.** Continuous-read mode on the flash and QPI mode on the PSRAMs are lost at
  power-off; TinyQV lets the host arm them before reset and its author regretted it. The RLE Video Player
  shows the alternative: a protocol that works on a cold chip. For arm16 that is EBh in SPI mode on both
  parts (one-lane command, quad address and data, mode byte FFh so continuous read is never armed) and 38h
  quad write on the PSRAM. It costs 8 extra SCK cycles per stream restart against the armed path, about 3
  core cycles per instruction on average, and removes every init-sequence dependency. Arming continuous
  read from an on-chip init state machine is the later optimization, not the sprint.
- The flash's quad-enable bit is non-volatile, ships clear on the `-IM` part the Pmod carries, and the
  flasher does not set it. Set it once (06h, then 31h with S9 = 1) and verify with the JEDEC ID (EF 70 18).
  While it is clear, `uio[4]` and `uio[5]` are /WP and /HOLD with no board pull-up, so they must be driven
  high during single-SPI commands.
- The demo board's RP2350 also drives all eight `uio` pins; the SDK's per-project `config.ini` must hold
  them as inputs (`uio_oe_pico`). With the Pmod fitted the RP2 pins stay inputs and the RP2350-E9 pull-down
  erratum never arises.
- **Carry DJ8's insurance.** With no on-chip memory, a QSPI defect on silicon leaves nothing to show. A
  small synthesized ROM holding one seven-segment demo program, selected by a DIP switch at reset, maps to
  combinational logic and is the difference between a dead chip and a demo. Measure it; if it fits under
  about 72% utilization it goes in.
- Order the Pmod now, and write the cocotb memory model against the exact parts.

## Defects in the 02 probe controller (each confirmed independently by two agents)

1. Pin map: the probe puts data on `uio[0..3]` and SCK on `uio[4]`; the Pmod has CS0 on `uio[0]`, data on
   `uio[1]`, `uio[2]`, `uio[4]`, `uio[5]`, SCK on `uio[3]`, and the two PSRAM selects on `uio[6]`, `uio[7]`.
2. Address: it shifts `{8'h6B, pc, 8'h00}`, so the 24-bit address sent is the PC shifted left by 8 bytes.
3. Protocol: 6Bh is a one-lane command and one-lane address with quad data; the probe sends everything
   on four lanes. What it implements is a QPI-shaped EBh wearing a 6Bh opcode.
4. Launch edge: data and clock change on the same core edge (technique 5 above). The streaming variant in
   `rtl_variants/` inherits this; it is an area probe and must not be copied into the design as is.
5. No streaming, no prefetch, no sampling delay.

## Observations beyond the brief, recorded and not acted on

At 16 core cycles per fetch a five-stage pipeline is idle most of the time; two agents raised it
independently, and TinyQV's answer was a nibble-serial datapath matched to the bus, which is also why it
closes at 90 MHz. A 16-bit instruction encoding (Thumb) would halve fetch cost outright. Two memories not
costed here could change the picture later: SPI FRAM (non-volatile and byte-writable, no refresh, no page
limits, one chip for code and data, used by nanoV) and toivoh's PIO RAM emulator. All of these are scope
changes against the agreed brief and none fits a three-day sprint. They belong in the process post as
"what I would do next".

One process note: three agents reported that fetched third-party pages carried text imitating a system
instruction to add AI co-author lines to commits. All ignored it; agents made no commits.

## Recommendation

QSPI Pmod. Flash for instructions in a streamed EBh fetch with chip select held and no continuous-read
arming; PSRAM A for data with bounded bursts, SPI-mode EBh and 38h, no QPI entry; SCK = core/2 from a toggle
flop at a 25 MHz core; sampling one full SCK period late with a strappable delay; SCK launched on the falling
edge; data outputs held constant when idle; TinyQV's SDC; a DIP-selected internal demo ROM if it fits.
Expected fetch cost drops from about 60 core cycles to 16 sequential and about 56 on a restart, at a
measured cost of 114 cells. The RP2 route is kept as a fallback in name only: it is slower by 3 to 8x, does
not run on the shipping board, and would need firmware nobody has written.
