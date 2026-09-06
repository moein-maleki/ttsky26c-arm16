# Codex review 1 (Task 2 snapshot, commit 0a52e6b)

Reviewer: Codex (GPT-5) through the MCP, read-only sandbox, 2026-09-06. Prompt: review the RTL and the
testbench against spec sections 3.1, 3.2, 3.4, 3.5, 7, 8, 10 and the dialect. Thirteen findings.

| # | Finding (reviewer's words, shortened) | Verified | Disposition |
|---|---|---|---|
| 1 | P0: `info.yaml` lists only `project.v`; the TinyTapeout flow cannot elaborate the design | yes | fixed: all fourteen source files listed |
| 2 | P1: the UART is not implemented; TX tied high, UART_DATA and UART_STAT read zero | yes, planned | Task 5 |
| 3 | P1: every test skips unless ROMTEST is set; no gate-level path | yes | fixed before the review landed: ROMTEST defaults to yes for RTL builds, flash-fed tests run at gate level |
| 4 | P1: the flags path (forwarding mux, shifter, ALU, negedge status register) has half a period, 54 levels | yes, structural | fixed: the status register writes on the rising edge and is bypassed into decode (`cond_flags`), plan D10; the register file keeps its falling-edge write (short path) |
| 5 | P1: coverage gaps against spec 14.4 (UART, real ROM, VGA, flash literals, PSRAM, counts, backpressure, sweep) | yes, planned | Tasks 3 to 5 add every item; the odd-address-plus-branch-plus-backpressure scenario is in the flash random programs and the backpressure test |
| 6 | P2: odd load/store addresses reach the engine with bit 0 set | yes | fixed: bit 0 cleared in the engine address mux |
| 7 | P2: MRS decodes as TST with a flag update | yes | fixed: TST and CMP opcodes need S = 1, else NOP; model and assembler aligned; regression words added |
| 8 | P2: the VGA glyph is one pixel left of the sync coordinate | yes | fixed before the review landed (lit registered with active); pixel-exact frame test passes |
| 9 | P2: weak regressions (neutral cond-1111 payload, r0 = 7 bubble, load-use with equal values, loop seeds only with forwarding, negative test too broad) | yes | fixed: non-neutral payload, load-use with a stale value, loop seeds on both settings, and every ROM-mode run now compares the retired-instruction count with the model, which catches a phantom bubble directly; the expect-fail test is kept as the spec's "known to see" item and the flash suite adds a positive corruption-detection test |
| 10 | P2: the shipped ROM is never executed by the RTL suite | yes | `test_shipped_rom_boot` runs in the plain build (ROMTEST=no); the gate-level netlist carries the real ROM; a pytest proves `demo_rom.v` equals the assembled program |
| 11 | P3: ROM fetches above 0x3F alias to entry 0 | yes | accepted and documented (plan D11): in ROM mode the ROM repeats every 64 bytes; the shipped program never leaves it |
| 12 | P3: the assembler truncates oversized immediates | yes | fixed: values outside -32768..65535 are rejected |
| 13 | P3: STR of r15 accepted without defined semantics | yes | fixed: loads and stores of r15 are NOPs in the decoder, the model and the assembler (plan D2 extended) |

Checks the reviewer reported clean: Yosys structure (no latches, no multiple drivers, no loops), dialect
report, TinyTapeout port names and widths, every output driven, no clock gating, the reset synchronizer,
the strap latches, the supported flag logic, the condition table, forwarding priority, the load-use stall,
branch flush, BL link, PC + 8 reads, r15 writes, the bubble path, and the ADCS/SBCS fix.
