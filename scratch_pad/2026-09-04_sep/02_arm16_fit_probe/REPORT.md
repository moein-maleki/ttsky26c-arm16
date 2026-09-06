# Does a 16-bit, cache-less, fully featured ARM pipeline fit a 2x2 tile? — probe

> 2026-09-04. Question from the user: keep the 5-stage pipeline, forwarding, hazard detection, condition
> codes and all other features; drop only the cache; narrow the datapath to 16 bits; store each 32-bit
> instruction as two 16-bit words in an external QSPI flash; fetch instructions and data serially. Same flow
> as `01_tinytapeout_feasibility`: Yosys + ABC against `sky130_fd_sc_hd__tt_025C_1v80.lib`, placed area =
> synthesis area x 1.487. The 2x2 core is 72,565 um^2.

## Answer: it fits at about 65% utilization, which is above the safe line and below what has closed before

| Metric | 16-bit core with QSPI | 32-bit arm-cache | 2x2 reference |
|---|---|---|---|
| Standard cells | 3,403 | 34,791 | about 4,200 at 47% |
| Flip-flops | 616 | 10,586 | about 1,500 |
| Synthesis area | 31,668 um^2 | 443,250 um^2 | |
| Placed estimate | 47,090 um^2 | 659,113 um^2 | |
| Tile utilization | **64.9%** | 908% | logos 14.2%; warplet safe line 47%; tryte closed 74.6%; tryte failed 84% |

Against the budgets: 138% of the safe 47% line, 108% of the 60% line, and 87% of the 74.6% that tryte closed
successfully. So it is not comfortable and it is not hopeless. It needs a real hardening run to know, and that
run should target a clock below 40 MHz (see timing).

## What was built for the measurement

`rtl/` holds the probe. Every original module is present with its datapath narrowed from 32 to 16 bits by
substitution; the 32-bit ARM instruction encoding and its decode are untouched. Three modules were rewritten
structurally:

- `IF_stage.v`: 16-bit program counter, instruction supplied by an external fetch unit with a ready handshake.
- `MEM_stage.v`: the cache and asynchronous SRAM controller replaced by a request/ready port that stalls the
  pipeline until the serial memory answers. Forwarding and write-back paths unchanged.
- `qspi_master.v`: a new four-bit-wide QSPI master serving both instruction fetch (32 bits as two words) and
  data access from a flash-plus-PSRAM Pmod. Command, 24-bit address, dummy cycles, then four bits per clock.
- `arm16_top.v`: TinyTapeout pin wrapper. QSPI takes 7 of the 8 bidirectional pins. The 8 outputs show the
  program counter, selected by a switch, so the chip has something observable.

Retained: five pipeline stages, forwarding unit, hazard detection, condition check, status register, barrel
shifter (`val2_generator`), full 32-bit instruction decode. Removed: cache, SRAM controller, DE2 wrapper,
the 47-instruction ROM baked into the fetch stage.

**This is an area probe, not a verified design.** The width substitution is mechanical and the result has not
been simulated. It is structurally faithful, which is what an area number needs, and nothing more.

## Where the area goes (flattened total 31,668 um^2)

| Block | Cells | Flops | Synth um^2 | Share |
|---|---|---|---|---|
| Register file, 15 x 16 bits, two read ports | 1,038 | 240 | 13,445 | 42% |
| Execute stage: ALU, shifter, condition check, branch | 905 | 0 | 5,718 | 18% |
| QSPI master | 527 | 127 | 4,461 | 14% |
| ID/EX pipeline register | 313 | 104 | 3,520 | 11% |
| Fetch stage and IF/ID register (each holds a 32-bit instruction) | 322 | 96 | 3,450 | 11% |
| EX/MEM and MEM/WB registers | 231 | 77 | 3,082 | 10% |
| Decode, hazard, forwarding, control, status, write-back | ~150 | 4 | ~1,290 | 4% |

The per-block figures come from separate runs and sum a little above the flattened total because flattening
optimizes across boundaries; the flattened number is the real one. The register file is instantiated inside
`ID_stage`, so a naive per-module table counts it twice.

## Timing

Longest combinational path is 56 generic gate levels, measured with flip-flops recognised as path breakers.
The same measurement on logos gives 19 levels, and logos closed 40 MHz with 12.4 ns of slack on a 25 ns
period. Three times the depth makes 40 MHz doubtful without restructuring; 20 to 25 MHz is plausible. The
path runs from the register-file read multiplexer through forwarding, the shifter and the 16-bit ALU to the
branch decision. TinyTapeout lets the design set its own clock, and with serial fetch the core clock is not
the performance limit anyway.

## Performance reality

Every instruction is fetched over QSPI: roughly 8 command, 6 address, 6 dummy and 8 data nibble-cycles, so
around 28 QSPI clocks, or about 56 core clocks at the half-rate QSPI clock in the probe. Loads and stores add
a similar transaction. The pipeline therefore completes on the order of one instruction per 60 cycles. At
25 MHz that is roughly 400 thousand instructions per second, which is plenty for a demo program driving a
display, and far too slow for the forwarding and hazard logic to matter for throughput. Those features remain
present, testable and demonstrable, but they will not be what makes the chip fast.

## Levers if the hardening run comes in too tight

1. The 32-bit instruction is held twice, in the fetch stage and again in the IF/ID register: 64 flops. One
   copy is enough.
2. The QSPI master keeps a 32-bit shifter, a 32-bit receive register and a 32-bit instruction output: 96
   flops. They can share.
3. Run at 20 MHz rather than 40 MHz, which lets the flow use smaller cells and less buffering.
4. The register file at 240 flops is the floor. Cutting registers was ruled out, so it stays.

Those three together are worth roughly 15% of the area and would bring utilization near 55%.

## Caveats

Single liberty corner, no placement or routing, no signoff timing, no functional simulation. The x1.487
placement factor came from tryte and was accurate within a few percent for logos.
