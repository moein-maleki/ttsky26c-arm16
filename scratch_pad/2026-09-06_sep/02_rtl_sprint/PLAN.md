# arm16 RTL-to-GDSII Sprint Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline, this session) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. The calendar is the constraint: TTSKY26c closes 2026-09-07 20:00 UTC.

**Goal:** Build, verify, harden, push and CI-prove the arm16 chip described in `docs/spec.md` v0.3, from a fresh copy of the lab ARM pipeline, in the verilog-rewrite dialect, with a software testbench (golden model, encoder, image loader) and a hardware testbench (cocotb with behavioural flash and PSRAM models), reviewed by Codex at each block boundary.

**Architecture:** One structural TinyTapeout top wraps one `arm16_controller` (the fetch, bus and pipeline-flow sequencer) and one `arm16_datapath` (the five-stage pipeline, register file, ALU, shifter, peripherals) which instantiates the functional units (`qspi_master`, `vga_renderer`, `uart_transceiver`, `demo_rom`, decoder, hazard and forwarding units). Instructions stream from the QSPI flash with chip select held; data lives in the PSRAM; a hardware renderer paints a 16-bit value as four digits on the TinyVGA Pmod. The golden model, not the lab RTL, is the reference.

**Tech Stack:** Verilog-2001 (verilog-rewrite dialect, checked by `check_dialect.py`), Icarus + cocotb 2.x from `~/oss-cad-suite`, Yosys for area, librelane 3.0.3 + sky130A `8afc834` via `tt/tt_tool.py`, Codex MCP (read-only sandbox) for reviews, `gh` for the repository and CI watch.

**Spec:** `designs/ttsky26c-arm16/docs/spec.md` (v0.3). Supporting: `scratch_pad/2026-09-04_sep/03_memory_options/PLAN.md` (eleven RTL rules), `scratch_pad/2026-09-06_sep/01_architecture_exploration/evidence/plan_review_risk.md` lines 98 to 109 (the order of work and kill criteria; the board, todo and handoff point at "REPORT.md section 7", which is the risk section, not the order), `~/.agents/skills/verilog-rewrite/references/verilog-dialect.md` (the dialect), `verilog-dialect.md` lines 478 to 667 (the canonical four-module example to copy structurally).

## Context

The spec was agreed on 2026-09-06 after three sessions of measurement (memory options, cache, VGA, architecture exploration). No RTL exists: `src/project.v` is the template placeholder. The user chose TTSKY26c on the held 2x2 tile with about 36 hours left, and asked for: execution of the spec; a fresh copy of the lab code as the starting point; new code in the verilog-rewrite dialect; testbenches in software and hardware that catch program-loading errors and hardware bugs; Codex reviews of code, testing and hardening; GDSII; a push that passes the TinyTapeout CI; and the CI watched to completion.

Three facts from the exploration shape the plan. First, the probe RTL (`scratch_pad/2026-09-04_sep/02_arm16_fit_probe/rtl/`) carries every audited defect: its flush bubble is `ANDEQ r0,r0,r0` with a write enable, it re-issues fetches after a freeze, its ALU flags read bit 31 of a 16-bit result and compute carry from signed operands, and its QSPI controller has the wrong pin map, a byte-shifted address, a one-lane command sent on four lanes and a same-edge clock launch. None of it is copied; the lab's decode tables and pipeline structure are. Second, the dialect checker forbids procedural blocks in the top and pairs every non-public controller and datapath port, and its public-signal closure follows only the top's `assign` statements, so every pin-facing unit must live inside the datapath. Third, the area cap is 72% at the synthesis estimate (35,134 um^2 of Yosys `stat` area, placed x1.487 over 72,565 um^2) and the probe already measures 64.9%, so every block is synthesized when it lands and the drop order of spec section 11 applies.

## Global Constraints

- Shuttle TTSKY26c, one 2x2 tile, `clock_hz: 25000000`, top module `tt_um_moein_maleki_arm16`, `info.yaml` already carries these.
- Deadline 2026-09-07 20:00 UTC (verified against `https://app.tinytapeout.com/api/shuttles/ttsky26c` on 2026-09-06 07:42 UTC). Kill criterion at hour 30 of the sprint: ship with the ROM mode verified and the controller marked unverified in `docs/info.md` if the bus tests have not passed.
- Area cap 72% at the synthesis estimate: Yosys flattened `stat -liberty` area at most 35,134 um^2. Measure after every block with the command in Task 0. Drop order when over the cap: meter, UART receive, UART.
- Core clock 25 MHz fixed (pixel clock); memory clock 12.5 MHz from a toggle flop launched on the falling core edge; SCK ratio is the engine parameter `TICK_RATIO = 2`.
- Memory: QSPI Pmod on all eight `uio` pins; SPI-mode EBh reads on both chips, 38h PSRAM write; no volatile chip mode; PSRAM chip select low at most 6 us (hard counter); never execute from PSRAM; data pins hold their last value when idle.
- Every RTL file: strict Verilog-2001, `.v`, one module per file, file name equals module name (exception `src/project.v` holds the `tt_um_` top), starts with `` `default_nettype none `` and ends with `` `default_nettype wire `` and carries no other directive, ANSI ports with the direction repeated on every port, named connections only, lower_snake_case names, UPPER_SNAKE parameters, internal ports suffixed `_in`/`_out` (`clk`, `rst` exempt), instance names `<module_function>_unit`, section order: functions/parameters, wires, regs, assigns, clocked blocks, `next_state` block, other `always @*`, instances. Combinational blocks `always @*` with blocking assignments and defaults before any `if`/`case`; clocked blocks nonblocking only; one procedural owner per register; no latches, no `initial`, no `x` defaults, no internal `z`.
- No AI attribution anywhere (commit messages, code, docs). No push before Task 9. Commit at every block boundary with a substantive message.
- Tools: `source ~/oss-cad-suite/environment` for simulation and Yosys; `source ~/.venvs/librelane/bin/activate` and `PDK_ROOT=/home/moein/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71` for hardening and gate level; `tt/` is a local clone at `d65690e` (ignored); `arm-none-eabi-as` is not installed (Python encoder is the assembler for the sprint; the byte-for-byte cross-check test skips when the tool is absent).
- Durable artifacts go to `scratch_pad/2026-09-06_sep/02_rtl_sprint/` (`PLAN.md` = this file, `REPORT.md`, `INFRA_AND_COMMANDS.md`, `evidence/`, `scripts/`, `reviews/`). The dialect checker's outputs must live outside the design tree; run it into the session scratchpad and copy the JSON into `evidence/`.

---

## Decisions taken by this plan (say so if any is wrong)

- **D1 Shifter carry and the `#0` shift encodings.** C is unchanged by logical operations (AND, ORR, EOR, TST, MOV, MVN) and by the shifter; the ARM shifter-carry rule is not implemented. Shift amounts are the literal 5-bit immediate on the 16-bit value (LSL/LSR by 16 or more give 0, ASR by 16 or more gives the sign fill, ROR uses the amount modulo 16). The ARM special encodings LSR #0 = LSR #32, ASR #0 = ASR #32 and ROR #0 = RRX are not supported; the encoder rejects them. Reason: about 50 cells and four special cases of test surface for no demo value. Recorded in spec section 3.1 as a deviation.
- **D2 Register 15 as a destination.** A data-processing write to r15 branches to the result (spec); the register file has no r15 entry. LDR with Rd = r15 executes as a NOP (spec: not supported).
- **D3 One source of truth for the restart address.** The delivered word D is dropped on every abort (taken branch, write to r15, data access) and the stream always restarts at `fetch_addr`, which changes only on a redirect load or on an accept (`valid && ready && !redirect`), never on `word_valid`. Keeping D across a data access would save 16 cycles per load at the cost of a second restart address; it is parked.
- **D4 Stream pause.** The engine launches the first SCK request of a new stream word only when `word_room_in` says a landing register is free (D empty, or D being accepted this cycle). When the pipeline is stalled and R fills, SCK stops low with the chip select still low (TinyQV's stall) and resumes on the next tick after the accept; the pause is at a word boundary, never mid-nibble.
- **D10 Status register on the rising edge with a bypass (from Codex review 1).** The negedge status register put the forwarding mux, shifter and ALU on a half-period path (54 levels). The flags now write on the rising edge; decode reads `cond_flags = flags_write ? flags_next : nzcv`, so a conditional instruction right after CMP still sees the new flags in the same cycle; the execute stage reads the snapshot taken into ID/EX. The register file keeps its falling-edge write (a short path). Spec 3.2 wording updated in v0.4.
- **D11 ROM range.** In ROM mode the sixteen-word ROM repeats every 64 bytes for any fetch address (bits [5:2] decoded); the shipped program never leaves 0x00 to 0x3C. The model mirrors it.
- **D12 The delivered word D is the decode-stage register.** There is no separate IF/ID register: decode reads D (streamed path) or the ROM word at `fetch_addr` (ROM mode) directly, `fetch_addr` is the PC of the instruction in decode, an accept (`if_id_load`) increments it and clears `d_valid` unless a refill lands in the same cycle, a redirect drops D. Saves 48 flops and one cycle of fetch latency; decided at 80.4% measured after the engine landed.
- **D13 UART cut (spec section 11 drop order).** With the engine in place the design measured 80.4%; the ALU (one adder), the shifter (one rotator with masks), D12 and the removal of the UART divider brought it to 71.7%. The meter stays. UART_EN still blanks the video and rests the transmit pin high; UART_DATA, UART_STAT and UART_DIV read 0. Recorded in spec v0.4 and `docs/info.md`.
- **D9 Sampling rule (corrects spec 3.3 and 12 wording in v0.4).** Both chips launch read data after the SCK falling edge (tCLQV, SPI mode 0) and expect the master to sample on the rising edge. The engine captures `sd_in` on the core rising edge that is `rx_delay` (1 to 3) core clocks after the core rising edge on which it cleared `sck_reg` (the tick whose negedge copy launches the falling edge that clocks the nibble out of the chip). With the 20 ns core half-period this samples 20, 60 or 100 ns after the pad falling edge; strap 1 passes for a mux round trip up to 11 ns, strap 2 for 0 to 40 ns, strap 3 from 20 ns up, so two straps pass at 20 and at 30 ns as section 14 requires. The spec's "one full memory clock after the launch edge plus 1 to 3 core clocks" is replaced by this sentence.
- **D5 UART.** Transmit and receive are written together (about 120 cells); receive is the first thing cut after the meter if the cap breaks. Loopback test needs receive.
- **D6 Dialect enforcement.** The form rules are mandatory in every file. `check_dialect.py` runs after every block. If its controller/datapath state-ownership classifier rejects a pipeline structure that the form rules allow, and the fix is not obvious within one hour, the residual errors are recorded verbatim in `REPORT.md` as accepted limitations rather than spending sprint hours on them.
- **D7 Gate-level frame test.** The full-frame capture (420,000 cycles) runs at RTL; at gate level the same test renders the 160 scanlines of the digit band (about 128,000 cycles) and compares that band. Everything else runs identically at both levels.
- **D8 Demo ROM program** (16 words, addresses 0x00 to 0x3C): counts on the screen at about 27 increments per second with forwarding on and about 2.3x slower with it off.

```
0x00  MOV  r0, #0
0x04  MOV  r10, #0
0x08  MOV  r1, #0xFF00        ; imm8 0xFF rotated right by 24 = 0xFF00 in the 16-bit ring
0x0C  loop: ADD r2, r0, #1    ; eight-deep dependent chain
0x10  ADD  r3, r2, #1
0x14  ADD  r4, r3, #1
0x18  ADD  r5, r4, #1
0x1C  ADD  r6, r5, #1
0x20  ADD  r7, r6, #1
0x24  ADD  r8, r7, #1
0x28  SUB  r0, r8, #7         ; r0 = r0 + 1
0x2C  CMP  r0, #0
0x30  ADDEQ r10, r10, #1      ; r10 counts wraps of r0 (every 65536 loops, about 37 ms)
0x34  STR  r10, [r1, #0]      ; VGA_VAL = r10 (peripheral store, no bus)
0x38  B    loop
0x3C  B    0x3C               ; unused entry branches to itself
```

---

## File structure

| File | Module | Role | Responsibility |
|---|---|---|---|
| `src/project.v` | `tt_um_moein_maleki_arm16` | top | Structural: pin glue (`assign`), `arm16_controller_unit`, `arm16_datapath_unit`, `reset_synchronizer_unit`. No `reg`, no `always`. |
| `src/reset_synchronizer.v` | `reset_synchronizer` | functional_unit | `rst_n` asynchronous assert, two-flop synchronous release; output `rst` active high. |
| `src/arm16_controller.v` | `arm16_controller` | controller | `present_state`/`next_state` FSM: ROM mode, stream start, streaming, restart, data access, hold; one output-decode block for the seventeen commands of the boundary table (`stream_start_out` ... `mem_busy_out`). |
| `src/arm16_datapath.v` | `arm16_datapath` | datapath | Strap latches, PC and parked fetch word, IF/ID, ID/EX, EX/MEM, MEM/WB registers, flags, address decode, peripheral registers, meter, display selection, pin muxing; instantiates all units below. |
| `src/instruction_decoder.v` | `instruction_decoder` | functional_unit | Combinational: fields to class, execute command, `wb_en`, `mem_read`, `mem_write`, `branch`, `link`, `has_src1`, `has_src2`, `set_flags`, `dest`, `src1`, `src2`, `is_valid` (cond != 1111). |
| `src/condition_checker.v` | `condition_checker` | functional_unit | Combinational: 16 conditions on NZCV. |
| `src/register_file.v` | `register_file` | functional_unit | 15 x 16, two read ports, one write port on `negedge clk`, no reset. |
| `src/barrel_shifter.v` | `barrel_shifter` | functional_unit | Combinational operand 2: rotated immediate, LSL/LSR/ASR/ROR by immediate, 12-bit load/store offset with the direction bit. |
| `src/alu.v` | `alu` | functional_unit | Combinational: MOV, MVN, ADD, ADC, SUB, SBC, AND, ORR, EOR; N Z C V per the ARM definition on 16 bits. |
| `src/hazard_detector.v` | `hazard_detector` | functional_unit | Combinational: load-use stall (forwarding on) or any RAW stall (forwarding off). |
| `src/forwarding_selector.v` | `forwarding_selector` | functional_unit | Combinational: MEM-over-WB source selects for both operands. |
| `src/demo_rom.v` | `demo_rom` | functional_unit | Combinational 16 x 32-bit lookup of D8. |
| `src/qspi_master.v` | `qspi_master` | functional_unit | Bit-level QSPI engine with its own local protocol FSM: stream, flash word read, PSRAM read, PSRAM write, abort, pause, strap delay sampler, tCEM counter. |
| `src/vga_renderer.v` | `vga_renderer` | functional_unit | 640x480 timing and the four-digit renderer (from `06_vga_question/rtl/vga_seg4.v` + `vga_timing.v`, restyled). |
| `src/uart_transceiver.v` | `uart_transceiver` | functional_unit | 8N1 transmit and receive, divider register input. |
| `test/arm16_asm.py` | | software testbench | Encoder for the subset with labels; image builder; reference decoder for round-trip tests. |
| `test/arm16_model.py` | | software testbench | Golden model from the ARM definition: registers, flags, address map, peripherals, retired count, bus-transaction count. |
| `test/qspi_models.py` | | hardware testbench | cocotb `FlashModel` (W25Q128JV) and `PsramModel` (APS6404L) bound to the DUT pins. |
| `test/test_software.py` | | software testbench | pytest: encoder, model flag semantics, image loading, cross-check vs `arm-none-eabi-as` (skips if absent). |
| `test/test.py` | | hardware testbench | cocotb suite (RTL and gate level). |
| `test/programs/*.s` | | | Directed and demo programs in the subset syntax. |
| `docs/info.md`, `info.yaml`, `src/config.json` | | | TinyTapeout metadata: pinout, source list, how it works, how to test, external hardware. |

Dialect plan file (kept outside the tree during the check, copied to `evidence/`): `rewrite-plan.json` with `schema_version: 1`, `top_module: "tt_um_moein_maleki_arm16"`, and one `{path, module, role}` record per file above.

---

## Interfaces

### Top-level pins (spec section 7)

`ui_in`: [0] FWD_EN (strap), [1] DISP_SEL, [2] UART_EN, [3] UART_RX, [4] QSPI_DLY0 (strap), [5] QSPI_DLY1 (strap), [6] BOOT_ROM (strap), [7] USER. Straps are latched while `rst` is active.
`uo_out` video: [0] R1, [1] G1, [2] B1, [3] VSYNC_n, [4] R0, [5] G0, [6] B0, [7] HSYNC_n. With UART_EN = 1: [4] = UART_TX, [3] = [7] = 1, others 0.
`uio`: [0] CS_FLASH_n out, [1] SD0, [2] SD1, [3] SCK out, [4] SD2, [5] SD3, [6] CS_RAM_A_n out, [7] CS_RAM_B_n out held 1. `uio_oe` per data pin from the engine; [0], [3], [6], [7] always output.

Top glue (all `assign`, keeps every controller/datapath pin-side port public for the checker):

```verilog
assign qspi_sd_in  = {uio_in[5], uio_in[4], uio_in[2], uio_in[1]};
assign uio_out     = {cs_ram_b_n, cs_ram_a_n, qspi_sd_out[3], qspi_sd_out[2], qspi_sck, qspi_sd_out[1], qspi_sd_out[0], cs_flash_n};
assign uio_oe      = {1'b1, 1'b1, qspi_sd_oe[3], qspi_sd_oe[2], 1'b1, qspi_sd_oe[1], qspi_sd_oe[0], 1'b1};
assign uo_out      = video_pins;   // datapath output, already muxed with the UART
```

### Controller to datapath boundary (each pair is one top wire; names normalise to the same meaning)

Status into the controller (`arm16_datapath` outputs `<x>_out`, `arm16_controller` inputs `<x>_in`):

| Meaning `<x>` | Width | Produced by |
|---|---|---|
| `rom_mode` | 1 | BOOT_ROM strap latch |
| `busy` | 1 | engine: 1 from a start until the chip-select-high gap has elapsed |
| `word_valid` | 1 | engine: the receive register R holds a complete stream word |
| `data_done` | 1 | engine: pulse, a data transaction finished (`rdata[15:0]` valid for a read) |
| `redirect` | 1 | EX stage: taken B/BL or a write to r15 with the condition met (a level while the instruction sits in EX) |
| `mem_access` | 1 | MEM stage holds an LDR/STR whose address is flash or PSRAM (not a peripheral) |
| `mem_write` | 1 | that access is a store |
| `addr_is_flash` | 1 | that access is in the flash range (address bit 15 = 0) |
| `hazard` | 1 | hazard detector: stall decode this cycle |

Commands from the controller (`arm16_controller` outputs `<y>_out`, `arm16_datapath` inputs `<y>_in`):

| Meaning `<y>` | Width | Effect in the datapath |
|---|---|---|
| `stream_start` | 1 | pulse: engine opens a flash EBh stream at `fetch_addr` |
| `stream_stop` | 1 | pulse: engine aborts the stream (ignored unless a stream is open; never aborts a data transaction) |
| `data_start` | 1 | pulse: engine runs one data transaction at the MEM-stage address |
| `data_flash` | 1 | that transaction is a flash literal read (else PSRAM) |
| `data_write` | 1 | that transaction is a PSRAM write (38h) else a read (EBh) |
| `word_take` | 1 | the controller takes R this cycle (clears `word_valid`) |
| `word_room` | 1 | a landing register is free; the engine may request the next stream word |
| `addr_sel` | 1 | engine address mux: 0 `fetch_addr`, 1 the MEM-stage address (bit 15 cleared for the PSRAM) |
| `fetch_addr_load` | 1 | `fetch_addr <= branch_target` (from EX, datapath-internal) |
| `fetch_addr_inc` | 1 | `fetch_addr <= fetch_addr + 4` (the accept; exactly once per accepted word) |
| `fetch_word_load` | 1 | the delivered-word register D loads R |
| `fetch_src_rom` | 1 | the word presented to IF/ID is the ROM word at `fetch_addr`, not D |
| `if_id_load` | 1 | IF/ID loads the presented word (`{fetch_addr, word, 1}`) |
| `if_id_bubble` | 1 | IF/ID loads the bubble `{16'h0, 32'hF000_0000, 1'b0}`; neither load nor bubble = hold |
| `id_ex_bubble` | 1 | ID/EX loads a bubble (hazard stall or flush) |
| `mem_busy` | 1 | freeze: every pipeline register holds, `fetch_addr` holds |

Engine ports (unit `qspi_master` inside the datapath; parameters `TICK_RATIO = 2`, `CS_LOW_MAX = 150`, `GAP_CYCLES = 2`): `clk`, `rst`, `rx_delay_in[1:0]`, `stream_start_in`, `stream_stop_in`, `data_start_in`, `data_flash_in`, `data_write_in`, `addr_in[15:0]`, `wdata_in[15:0]`, `word_take_in`, `word_room_in`, `sd_in[3:0]`; `busy_out`, `word_valid_out`, `data_done_out`, `rdata_out[31:0]`, `fault_out` (sticky: the tCEM counter forced CS_RAM high), `sck_out`, `cs_flash_n_out`, `cs_ram_a_n_out`, `cs_ram_b_n_out` (constant 1), `sd_out[3:0]`, `sd_oe_out[3:0]`. The datapath passes the controller's commands straight through to the unit (wire glue), captures `rdata_out[15:0]` into MEM/WB in the `data_done` cycle, and exposes `busy_out` to the hardware view as "bus active".

### Pipeline registers (datapath, positive edge, synchronous `rst`)

- IF/ID: `id_pc[15:0]` (address of the instruction), `id_instr[31:0]`, `id_valid`. Bubble = `{16'h0, 32'hF000_0000, 1'b0}`.
- ID/EX: `ex_valid`, `ex_pc[15:0]`, `ex_wb_en`, `ex_mem_read`, `ex_mem_write`, `ex_branch`, `ex_link`, `ex_set_flags`, `ex_dest[3:0]`, `ex_dest_is_pc`, `ex_execute_cmd[3:0]`, `ex_is_immediate`, `ex_is_memory`, `ex_up`, `ex_operand2_bits[11:0]`, `ex_val_rn[15:0]`, `ex_val_rm[15:0]`, `ex_src1[3:0]`, `ex_src2[3:0]`, `ex_has_src1`, `ex_has_src2`.
- EX/MEM: `mem_valid`, `mem_wb_en`, `mem_mem_read`, `mem_mem_write`, `mem_dest[3:0]`, `mem_alu_result[15:0]` (address for loads and stores), `mem_store_data[15:0]`.
- MEM/WB: `wb_valid`, `wb_wb_en`, `wb_mem_read`, `wb_dest[3:0]`, `wb_alu_result[15:0]`, `wb_load_data[15:0]`.
- Flags `nzcv[3:0]` write on `negedge clk` (reset to 0). Register file writes on `negedge clk` from the WB stage. r15 read in ID returns `id_pc + 8`. Link value = `id_pc + 4` (carried as `ex_pc + 4`). Branch target in EX = `ex_pc + 8 + sign_extend(imm24) << 2` truncated to 16 bits, or the ALU result for a write to r15.

### Address map in the MEM stage (spec section 8)

`addr[15:8] == 8'hFF` peripheral (one cycle, no bus); `addr[15] == 0` flash (load: bus kind 11; store: nothing); else PSRAM (bus kind 01/10, PSRAM byte address `{addr[14:1], 1'b0}`). Peripheral decode on `addr[7:1]`: 0x00 VGA_VAL rw, 0x02 SW r, 0x04 UART_DATA rw, 0x06 UART_STAT r, 0x08 UART_DIV rw (reset 217), 0x0C METER r, 0x10 VGA_FG rw (reset 6'b111111), 0x12 VGA_BG rw (reset 0). Unmapped reads 0, writes ignored.

### Instruction subset and encodings (spec section 3.1, lab decode tables)

Data processing (`instr[27:26] == 00`): opcode `instr[24:21]`: AND 0000, EOR 0001, SUB 0010, ADD 0100, ADC 0101, SBC 0110, TST 1000, CMP 1010, ORR 1100, MOV 1101, MVN 1111; RSB 0011, RSC 0111, TEQ 1001, CMN 1011, BIC 1110 execute as NOP. I = `instr[25]`, S = `instr[20]`, Rn `[19:16]`, Rd `[15:12]`, operand 2 `[11:0]` (immediate: `imm8 = [7:0]` rotated right by `2 * [11:8]` in a 16-bit ring; register: Rm `[3:0]`, type `[6:5]` LSL/LSR/ASR/ROR, amount `[11:7]`; bit 4 must be 0, else NOP). Load/store (`[27:26] == 01`): L = `[20]`, U = `[23]`, Rn, Rd, offset12 `[11:0]`; P = 1, W = 0, B = 0, I = 0 required, else NOP. Branch (`[27:25] == 101`): L = `[24]`, imm24 `[23:0]`. Mode 11 executes as NOP. Condition `[31:28]`, 1111 never executes (bubble marker).

Execute commands (lab codes kept): NOP 0000, MOV 0001, ADD 0010 (also LDR/STR address), ADC 0011, SUB 0100 (also CMP), SBC 0101, AND 0110 (also TST), ORR 0111, EOR 1000, MVN 1001.

Flags (16-bit, ARM definition): N = result[15]; Z = result == 0; C: ADD/ADC carry out of bit 15, SUB/SBC/CMP = NOT borrow (`{c, r} = a + ~b + 1` with unsigned operands); V: ADD/ADC `(a[15] == b[15]) && (r[15] != a[15])`, SUB/SBC/CMP `(a[15] != b[15]) && (r[15] != a[15])`; logical ops and MOV/MVN leave C and V unchanged (D1). Only S = 1 with `[27:26] == 00` updates flags; loads, stores and branches never do.

---

## Schedule (sprint hour 0 = first commit of Task 0)

| Hours | Task | Gate |
|---|---|---|
| 0 to 1 | 0 scaffold, tools, baseline reproduction, software testbench skeleton | baseline 3,403 cells reproduced; `pytest` runs |
| 1 to 9 | 1 encoder + golden model; 2 pipeline datapath, controller (ROM-style test fetch), units | directed tests per class and random differential pass at RTL in ROM mode; synth < cap; dialect check; Codex review 1 |
| 9 to 14 | 3 demo ROM, VGA, peripherals, hardware view, meter | ROM boot, frame capture, sync timing pass; synth; Codex review 2 |
| 14 to 26 | 4 QSPI engine + memory models + bus tests + flash programs | bus tests incl. sweep and tCEM pass; synth; Codex review 3 |
| 26 to 28 | 5 UART (if area) and negative test; final RTL synth; docs | full RTL suite green |
| 28 to 32 | 6 harden, 7 gate level, 8 precheck and metrics snapshot | STA/DRC/LVS/antenna clean; gate-level suite green; Codex review 4 |
| 32 to 34 | 9 push, CI watch, 10 close (report, index, memory) | test, docs, gds workflows green |
| 30 | kill criterion | if Task 4 is not green: freeze the RTL with ROM mode verified, mark the controller unverified, proceed to Task 6 |

---

## Task 0: Scaffold, tools, baseline, software testbench skeleton

**Files:**
- Create: `scratch_pad/2026-09-06_sep/02_rtl_sprint/{PLAN.md,INFRA_AND_COMMANDS.md,scripts/synth_area.sh,scripts/check_dialect.sh,scripts/run_tests.sh,evidence/,reviews/}`
- Create: `scratch_pad/2026-09-06_sep/02_rtl_sprint/lab_copy/` (fresh copy of `sandbox/computer-architecture-lab/arm-forwarding/*.v`, the provenance reference)
- Modify: `test/requirements.txt` (add `pytest`), `test/Makefile` (source list, `GATES` path as template), `.gitignore` (`test/sim_build`, `test/results.xml`, `__pycache__`, `runs/`, `tt/`)

**Interfaces:** Produces `scripts/synth_area.sh <top> <files...>` printing `cells N flops F area A util U%` and `scripts/check_dialect.sh` writing the JSON into the session scratchpad then copying it to `evidence/`.

- [x] **Step 1: Copy the lab code and record provenance.** `cp sandbox/computer-architecture-lab/arm-forwarding/*.v designs/ttsky26c-arm16/scratch_pad/2026-09-06_sep/02_rtl_sprint/lab_copy/`; write `lab_copy/PROVENANCE.md` with the lab commit (`af1a532`, fixes at `cc1fd9c`).
- [x] **Step 2: Reproduce the baseline.** Run the exact command from `scratch_pad/2026-09-04_sep/03_memory_options/INFRA_AND_COMMANDS.md` on the probe RTL; expect `cells 3403 flops 616`. Save the log to `evidence/baseline_repro.log`. Stop if it does not reproduce.
- [x] **Step 3: Write `scripts/synth_area.sh`:**

```bash
#!/usr/bin/env bash
# Usage: synth_area.sh <top> <log> <verilog files...>
set -euo pipefail
source ~/oss-cad-suite/environment
LIB=~/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
top=$1; log=$2; shift 2
yosys -p "read_verilog $*; synth -top $top -flatten; dfflibmap -liberty $LIB; abc -liberty $LIB; opt_clean -purge; stat -liberty $LIB" > "$log"
awk '/sky130_fd_sc_hd__/ {c+=$1} /sky130_fd_sc_hd__(df|edf|sdf|dl)/ {f+=$1} END {printf "cells %d flops %d ", c, f}' "$log"
grep 'Chip area' "$log" | tail -1 | awk '{a=$NF; printf "area %.0f util %.1f%%\n", a, a*1.487/72565*100}'
```

Never pass `-q` to yosys (the `stat` table disappears).
- [x] **Step 4: Write `scripts/check_dialect.sh`:**

```bash
#!/usr/bin/env bash
set -euo pipefail
repo=/home/moein/projects/lithos/designs/ttsky26c-arm16
out=/tmp/claude-1000/-home-moein-projects-lithos/73559d18-d5d6-448b-bcf2-89f0d63c3f51/scratchpad/dialect
mkdir -p "$out"; stamp=$(date -u +%Y%m%dT%H%M%SZ)
cp "$repo/scratch_pad/2026-09-06_sep/02_rtl_sprint/rewrite-plan.json" "$out/rewrite-plan.json"
/usr/bin/python3 /home/moein/.agents/skills/verilog-rewrite/scripts/check_dialect.py \
  --project "$repo" --rewrite-plan "$out/rewrite-plan.json" --output "$out/dialect_$stamp.json" || true
cp "$out/dialect_$stamp.json" "$repo/scratch_pad/2026-09-06_sep/02_rtl_sprint/evidence/"
python3 -c "import json,sys; d=json.load(open('$out/dialect_$stamp.json')); print('passed', d['passed']); [print(e) for e in d['errors']]"
```

- [x] **Step 5: Software testbench skeleton.** Create `test/arm16_asm.py`, `test/arm16_model.py`, `test/test_software.py` with the interfaces of Task 1 as stubs raising `NotImplementedError`, and `test/programs/`. Run `cd test && python3 -m pytest test_software.py -q`; expect collection to succeed and tests to fail on `NotImplementedError`.
- [x] **Step 6: Hardening configuration and signoff checker now, not at hour 28.** Edit `src/config.json`: `"CLOCK_PERIOD": 40` (25 MHz; the stock 20 is 50 MHz), `"PL_TARGET_DENSITY_PCT": 75` (the design will sit near 70% utilization; placement fails when utilization exceeds the density target; adjust from the `GPL-0019` line of the first harden), add `"EXTRA_EXCLUDED_CELLS": ["sky130_fd_sc_hd__clkdlybuf*"]` and `"PL_RESIZER_SETUP_SLACK_MARGIN": 0.6` (warplet's repair-design lesson: the flow split a critical fanout with a 25x clock-delay cell and failed setup by 0.562 ns). Copy `designs/ttsky26c-logos/scripts/check_signoff.py` and its `test_check_signoff.py` to `scripts/` (it asserts identity from `info.yaml` against the built netlist, nine corners, setup and hold counts and worst slack, the six physical zeros, and the `clkdlybuf` ban). Write `scripts/snapshot_harden.sh` (copies `runs/wokwi/final/metrics.json`, `runs/wokwi/55-openroad-stapostpnr/summary.rpt`, the `GPL-0019` utilization line, `runs/wokwi/final/pnl/*.pnl.v` and `runs/wokwi/01-verilator-lint/verilator-lint.log` into `evidence/harden_<stamp>/`).
- [x] **Step 7: Commit** `git commit -m "Sprint scaffold: lab copy, area and dialect scripts, hardening config, signoff checker, software testbench skeleton"`.

---

## Task 1: Encoder, image builder, golden model (software testbench)

**Files:** `test/arm16_asm.py`, `test/arm16_model.py`, `test/test_software.py`, `test/programs/directed_*.s`.

**Interfaces (produced):**

```python
# arm16_asm.py
def assemble(source: str, origin: int = 0) -> list[int]      # 32-bit words, labels resolved, raises AsmError
def encode(mnemonic: str, operands: str, cond: str = "AL", pc: int = 0, labels: dict = None) -> int
def build_flash_image(words: list[int], size: int = 32768) -> bytes   # little-endian, word i at byte 4*i
def decode(word: int) -> dict        # reference decoder used by the round-trip tests and the model
# arm16_model.py
class Arm16Model:
    def __init__(self, flash: bytes, boot_rom: list[int] | None = None, fwd_en: bool = True): ...
    regs: list[int]  # r0..r14 (start unpredictable: 0xDEAD pattern), pc: int, n z c v: bool
    psram: bytearray (32768); vga_val, vga_fg, vga_bg, uart_div: int; sw: int
    uart_tx_bytes: list[int]; bus_transactions: int; retired: int
    def step(self) -> None          # executes one instruction at pc
    def run(self, max_instr: int, stop_at_self_branch: bool = True) -> int
    def state_digest(self) -> dict  # regs, flags, psram sha1, vga_val, uart bytes
```

- [x] **Step 1: Write the failing tests** in `test/test_software.py` (pytest): (a) `test_encode_known_words`: `MOV r0, #20` == 0xE3A00014, `ADDS r1, r2, r3` == 0xE0921003, `SUBNE r4, r5, #1` == 0x12454001, `LDR r0, [r1, #4]` == 0xE5910004, `STR r0, [r1, #-4]` == 0xE5010004, `B .+8` (from pc 0) == 0xEA000000, `BL 0x100` from 0 == 0xEB00003E, `MOV pc, lr` == 0xE1A0F00E, `MOV r1, #0xFF00` == 0xE3A01CFF (imm8 0xFF, rot 12), `MOV r2, r3, LSL #4` == 0xE1A02203; (b) `test_encode_rejects`: register-specified shift, post-index, writeback, byte access, LSR #0, RSB all raise `AsmError`; (c) `test_decode_round_trip` over every encodable form; (d) `test_flags_definition`: model `ADDS` of 0xFFFF + 1 gives r = 0, N0 Z1 C1 V0; `SUBS` 0 - 1 gives 0xFFFF N1 Z0 C0 V0; `ADDS` 0x7FFF + 1 gives V1 N1; `SUBS` 0x8000 - 1 gives V1; `CMP` 5, 5 gives Z1 C1; `SBC` with C = 0 subtracts one more; `ADC` with C = 1 adds one; `MOVS` leaves C and V; `TST` sets N Z only; (e) `test_image_loading`: `build_flash_image(assemble(src))` places word i at bytes `4i..4i+3` little-endian and `Arm16Model(image).step()` executes word 0; a program placed at origin 0x100 via `origin` runs when pc is set there; (f) `test_model_semantics`: r15 read = pc + 8, BL writes r14 = pc + 4, `MOV pc, lr` returns, `B` backward loop terminates by count, LDR/STR to PSRAM round trip at 0x8000 + n, peripheral STR to 0xFF00 updates `vga_val`, unsupported opcode is a NOP that still retires; (g) `test_cross_check_binutils`: skip unless `arm-none-eabi-as` exists; else assemble each program with `-march=armv4`, `objcopy -O binary`, compare bytes.
- [x] **Step 2: Run** `python3 -m pytest test/test_software.py -q`; expect failures on `NotImplementedError`.
- [x] **Step 3: Implement `arm16_asm.py`:** parse `label:`, `; comment`, `.word`, `.org`, mnemonics with optional S and condition suffix (`ADDNES` and `ADDSNE` both accepted); operand forms `Rd, Rn, #imm`, `Rd, Rn, Rm[, SHIFT #n]`, `Rd, #imm`, `Rd, [Rn, #±off]`, `label`; encode immediates by searching `rot` in 0..15 for `imm8 ror (2*rot)` in the 16-bit ring, raise if none; reject everything outside the subset with a message naming the rule.
- [x] **Step 4: Implement `arm16_model.py`** from the ARM definition: fetch 32-bit little-endian word at pc from ROM (if boot_rom and pc < 0x40) or flash; condition check; decode via `decode()`; operand 2 per the subset (D1 for shifts); ALU with the flag rules above; loads/stores with the address map (a load from flash reads the 16-bit little-endian word; a store to flash is ignored; PSRAM at addr - 0x8000; peripherals as listed; UART_DATA write appends to `uart_tx_bytes`); B/BL/r15 semantics; `retired` counts every non-bubble instruction including failed conditions and NOPs; `bus_transactions` counts loads and stores to flash/PSRAM.
- [x] **Step 5: Run the tests to green;** `python3 -m pytest test/test_software.py -q` all pass (the binutils test skipped).
- [x] **Step 6: Commit** `git commit -m "Software testbench: ARM subset encoder, image builder, golden model with ARM flag semantics"`.

---

## Task 2: Pipeline datapath, controller and units (ROM-fed), hardware testbench core

**Files:** `src/project.v`, `src/reset_synchronizer.v`, `src/arm16_controller.v`, `src/arm16_datapath.v`, `src/instruction_decoder.v`, `src/condition_checker.v`, `src/register_file.v`, `src/barrel_shifter.v`, `src/alu.v`, `src/hazard_detector.v`, `src/forwarding_selector.v`, `src/demo_rom.v` (temporarily a test ROM), `src/config.json`, `test/test.py`, `test/tb.v`, `test/Makefile`, `rewrite-plan.json`.

**Interfaces:** As in the Interfaces section. In this task the `qspi_master` is absent (its status inputs to the controller are tied idle in the datapath) and every test runs in ROM mode (BOOT_ROM = 1), which is also the one-instruction-per-cycle regime where forwarding, the load-use stall and the flush actually fire.

**Test vehicle for ROM mode (RTL only).** The datapath passes the full fetch address `rom_address_in[15:2]` to the `demo_rom` unit; the shipped `src/demo_rom.v` decodes only bits [5:2] (16 entries, D8). For the RTL suite, `test/test_rom.v` defines a module with the same name and ports whose body is `reg [31:0] mem [0:1023]` indexed by `rom_address_in[11:2]`; cocotb writes the assembled program into `dut.user_project.arm16_datapath_unit.demo_rom_unit.mem[i]` before releasing reset, so no recompilation per program. `test/Makefile` selects `test_rom.v` instead of `src/demo_rom.v` when `ROMTEST=yes` (the RTL suite) and the real file otherwise (CI `test` job runs the RTL suite with the real ROM plus the flash-fed tests; the gate-level job runs the flash-fed tests only, since the netlist's ROM is fixed). Register and flag observation at RTL is by hierarchy: `...register_file_unit.regs[i]` and `...arm16_datapath_unit.nzcv`; these tests are marked RTL-only (`GATES != yes`). Every flash-fed test (Task 4) instead ends with the dump epilogue below, which works at gate level.

Dump epilogue (appended by `arm16_asm.epilogue()`; the golden model runs it too): `STR r0..r11, r13, r14` to PSRAM 0x8000 + 2k; then `MOV r0, #0; ORRMI r0, r0, #8; ORREQ r0, r0, #4; ORRCS r0, r0, #2; ORRVS r0, r0, #1; STR r0, [r12base, #flags]` (r12 is loaded with the base first and saved before it is overwritten); then `MOV r0, #0xD0; ORR r0, r0, #0xCE00` is not encodable in one instruction, so the done marker is `MOV r0, #0xCE; STR r0, [r12, #done]`; then `B .`. The test waits for the PSRAM model to see the write of 0x00CE at the done address, then compares the dump against `Arm16Model.state_digest()`.

Source lab modules to transform (fresh copy in `lab_copy/`): `control_unit.v` → `instruction_decoder.v` (add L bit of branches, the U bit, r15 handling, bit-4 and P/W/B checks, cond 1111 valid bit, NOP for unsupported opcodes); `condition_check.v` → `condition_checker.v` (table unchanged, LS fix kept); `register_file.v` → `register_file.v` (16 bits, no `initial`, no `rst`); `val2_generator.v` → `barrel_shifter.v` (16-bit ring rotation, U bit applied to the offset, D1 shift rules); `alu.v` → `alu.v` (unsigned operands, `{c, r} = a + b`, `{c, r} = a + ~b + cin`, V per the formulas, flags-out gated by `set_flags`); `hazard_detection.v` → `hazard_detector.v` (as fixed on 2026-08-10, with `id_valid`); `forwarding_unit.v` → `forwarding_selector.v`; the stage and stage-register modules → sections of `arm16_datapath.v` in data-flow order; the top-level wiring of `arm_processor.v` → `arm16_datapath.v` wiring.

- [x] **Step 1: Write the failing cocotb tests** in `test/test.py` (each writes its assembled program into the test ROM array, resets with BOOT_ROM = 1 and FWD_EN as given, runs until the model reports a self-branch plus a pipeline drain of 8 cycles, then compares `state_digest()` against the DUT registers and flags read by hierarchy, RTL only; if cocotb cannot write the array elements under Icarus, the fallback is a `$readmemh` `initial` block in `test/test_rom.v` fed by a per-program file and one `make` per program group): `test_directed_dataproc` (every opcode with S, immediate and register forms, flag checks after each), `test_directed_shifts`, `test_directed_branches` (B forward/back, BL + `MOV pc, lr`, r15 read = pc + 8, write to r15), `test_directed_conditions` (all 15 conditions taken and not taken), `test_unsupported_nop`, `test_lab_regressions` (the five 2026-08-10 cases re-encoded: load-use stall timing, branch beats stall, LDR/branch never update flags, MOV keeps C, LS condition), `test_bubble_never_writes` (a flush after `CMP` with Z = 1 leaves r0 unchanged and retires nothing extra), `test_random_differential` (200 random straight-line programs of 30 instructions plus 20 programs with one backward counted loop, FWD_EN 0 and 1, end state equal to the model), `test_hazard_stall_counts` (a known dependent chain retires in the model's cycle count under both stall policies, within the cycle model's numbers), `test_negative_known_failure` (deliberately expects a wrong register value and is marked `expect_fail`).
- [x] **Step 2: Run** `make -C test` and confirm the suite fails to compile (no RTL).
- [x] **Step 3: Write the RTL** in this order, each file checked with `iverilog -g2001` as it lands: `reset_synchronizer.v`, `condition_checker.v`, `register_file.v`, `barrel_shifter.v`, `alu.v`, `instruction_decoder.v`, `hazard_detector.v`, `forwarding_selector.v`, `demo_rom.v`, `arm16_datapath.v`, `arm16_controller.v` (ROM mode and the stall/flush/bubble decode; the stream states present but the engine status tied idle), `project.v` (rename the top from the template's `tt_um_example` to `tt_um_moein_maleki_arm16` here and in `test/tb.v`; `info.yaml` already carries the real name and `source_files` must list every `src/*.v`). Follow the section-order ranks and the naming rules exactly; copy the structural shape of `verilog-dialect.md` lines 478 to 667. Unit tests for the leaf units come first in `test/test.py` as separate cocotb tests on the top (they are cheap and they localize failures): `test_alu_flags_exhaustive_corners` drives ALU vectors through a two-instruction ROM program per vector class rather than poking the unit, because the top is the only compiled toplevel.
- [x] **Step 4: Run the suite** `make -C test`; iterate to green. Then `scripts/synth_area.sh tt_um_moein_maleki_arm16 evidence/synth_task2.log src/*.v` and record the numbers in `INFRA_AND_COMMANDS.md`; expect well under the cap (the probe core without the engine was about 2,900 cells).
- [x] **Step 5: Dialect check** `scripts/check_dialect.sh`; fix form errors; apply D6 to classifier errors.
- [x] **Step 6: Codex review 1** (protocol below) on `src/*.v`, `test/test.py`, `test/arm16_model.py`; verify each finding; fix what is real; save the exchange to `reviews/codex_review_1.md`.
- [x] **Step 7: Commit** `git commit -m "arm16 pipeline: datapath, controller, units in the dialect; ROM-mode cocotb suite green"`.

---

## Task 3: Demo ROM, VGA renderer, peripherals, hardware view, meter

**Files:** `src/demo_rom.v` (D8 contents), `src/vga_renderer.v`, `src/arm16_datapath.v` (peripheral registers, display selection, video/UART pin mux, meter), `test/test.py`, `test/vga_capture.py`.

- [x] **Step 1: Failing tests:** `test_rom_boot` (BOOT_ROM = 1, no memory models attached, both chip selects stay high for the whole run, VGA_VAL increments; with FWD_EN = 0 the increment rate is 2x to 2.6x slower), `test_peripheral_registers` (write/read VGA_VAL, VGA_FG, VGA_BG, UART_DIV; SW reflects `ui_in`; unmapped reads 0), `test_vga_sync_timing` (HSYNC period 800 pixels, low for 96; VSYNC period 525 lines, low for 2; active 640 x 480; polarity active low), `test_frame_capture` (render one frame to a PNG-free PPM in `sim_build/`, compare pixel-exactly against `vga_capture.reference_frame(value, fg, bg)` computed in Python from the renderer's geometry: digits in x 64..576, y 160..320, 32-pixel segments), `test_hardware_view` (DISP_SEL = 1 shows the PC white on black; with the bus active the background is dark blue 6'b000001; with USER = 1 the meter), `test_meter` (retired count of the previous frame latched at VSYNC).
- [x] **Step 2: Implement** `vga_renderer.v` from `06_vga_question/rtl/{vga_timing.v,vga_seg4.v}`: inputs `enable_in`, `value_in[15:0]`, `fg_in[5:0]`, `bg_in[5:0]`; outputs `pins_out[7:0]` in TinyVGA order, `vsync_out` (for the meter latch); registered outputs; colours blank when `enable_in` = 0. Datapath: registers VGA_VAL/FG/BG/UART_DIV, SW read, METER (`retired_count` reset each VSYNC into `meter_value`), display mux (`disp_sel ? (user ? meter : fetch_addr) : vga_val`, colours white/black-or-blue in hardware view), `video_pins` mux with UART_EN.
- [x] **Step 3: Green, synth, dialect, Codex review 2, commit** `git commit -m "Demo ROM, TinyVGA four-digit renderer, peripherals, hardware view, meter"`.

---

## Task 4: QSPI engine, memory models, bus tests, flash programs

The contract for this task is the section "QSPI engine and fetch sequencer design" at the end of this plan: lane orders, transaction tables, the timing table, the controller state table, the model behaviour and the eleven directed tests.

**Files:** `src/qspi_master.v`, `src/arm16_controller.v` (stream states), `src/arm16_datapath.v` (parked word, MEM-stage bus request), `test/qspi_models.py`, `test/test.py`.

- [x] **Step 1: Failing tests** (`FlashModel` and `PsramModel` attached to the `uio` pins; the flash image from `build_flash_image`): `test_stream_sequence` (straight-line program of 64 instructions: the flash model sees exactly one EBh command, chip select low throughout, the address sequence 0,4,8,... and the DUT retires all 64 in the model's order), `test_restart_on_branch` (each taken branch causes exactly one new EBh at the target; not-taken branches cause none), `test_data_access_interleave` (LDR/STR to PSRAM: the flash chip select rises, the PSRAM sees one EBh or 38h, the stream restarts at the right address; the count of PSRAM transactions equals the model's), `test_flash_literal_load` (LDR from a literal pool in flash), `test_backpressure_hold` (a hazard stall of several cycles while a word is parked: exactly one accept, the PC advances once, no duplicate or skipped instruction in the retired trace), `test_no_double_fetch_after_stall`, `test_delay_sweep` (mux round trip 0, 10, 20, 30, 40 ns x strap 1, 2, 3: a 32-instruction program must complete correctly; assert at least two straps pass at 30 ns), `test_psram_write_read` (store then load the same address, and a 1 KB fill/verify), `test_tcem` (a load-heavy program of 2,000 instructions: the PSRAM model fails the test if chip select stays low longer than 8 us or the gap is under 18 ns), `test_idle_pins_hold` (SD outputs unchanged while idle), `test_rom_mode_bus_quiet` (already in Task 3, rerun with the models attached), `test_transaction_count` (model `bus_transactions` == flash model + PSRAM model transaction counts for a random load/store program), `test_random_differential_flash` (the Task 2 random programs run from the flash).
- [x] **Step 2: Implement the memory models** (`qspi_models.py`): both sample the pins on the DUT's SCK edges using `RisingEdge(dut.uio_out[3])`/`FallingEdge` with a configurable `t_clqv_ns` delay applied with `Timer` before driving `uio_in`; decode per the phase tables; auto-increment; count transactions and bytes; raise `TestFailure` on protocol violations (unknown command, address on one lane, chip select high mid-byte, tCEM, tCPH).
- [x] **Step 3: Implement `qspi_master.v`** and the controller stream states per the design section; hand-verify the SCK launch on the negedge and the sampling rule in a waveform once (`tb.gtkw`).
- [x] **Step 4: Green, synth (this is the block that must show the rewrite's savings: target at most 3,517 cells for core + engine), dialect, Codex review 3, commit** `git commit -m "Streaming QSPI engine, flash and PSRAM models, bus and delay-sweep tests"`.

---

## Task 5: UART, negative test, final RTL synthesis, docs

**Files:** `src/uart_transceiver.v`, `src/arm16_datapath.v`, `test/test.py`, `docs/info.md`, `info.yaml`, `src/config.json`, `docs/spec.md` (deviations D1 to D8 recorded in section 17/3.1).

- [ ] **Step 1: Failing tests:** `test_uart_tx` (UART_EN = 1, program writes bytes; `uo_out[4]` decoded at 115,200 baud from UART_DIV 217; sync pins rest high, colours low), `test_uart_loopback` (tb ties `uo_out[4]` to `ui_in[3]`; program echoes; RX_VALID and RX_OVERRUN behave), `test_negative_known_failure` (kept).
- [ ] **Step 2: Implement `uart_transceiver.v`** (divider from `UART_DIV`, one TX holding byte, one RX holding byte with 16x-free majority-free mid-bit sampling at half divider, overrun flag). Synthesize; apply the drop order if over the cap.
- [x] **Step 3: Docs:** `docs/info.md` (how it works, how to test with the Pmods, external hardware, the pin table, the ROM demo), `info.yaml` pinout comments, `src/config.json` source list. Update `docs/spec.md` to v0.4: D1 (shifter carry and the `#0` encodings) in section 3.1, D9 (the falling-edge launch and the strap sampling sentence) in sections 3.3 and 12, D3 (restart always at the fetch address) in 3.3, the ROM-mode behaviour of a Pmod access in 3.5, and the measured numbers in 11.
- [x] **Step 4: Final RTL suite green** (`make -C test`), final synth numbers in `INFRA_AND_COMMANDS.md`, dialect check, commit `git commit -m "UART, documentation, final RTL synthesis under the cap"`.

---

## Task 6: Harden at 25 MHz

Precedent: logos and warplet hardened locally in 2.5 to 4 minutes per 2x2 run at 14% and 47% utilization; budget 5 to 10 minutes here and read the time from the first run. `--harden` deletes `runs/wokwi` first, so snapshot before every re-run. Flow exit 0 and "Flow complete" do not mean STA-clean: gate on the metrics.

- [x] **Step 1: Environment and user config.**

```bash
cd /home/moein/projects/lithos/designs/ttsky26c-arm16
source ~/.venvs/librelane/bin/activate
export PDK_ROOT=/home/moein/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71
git -C tt rev-parse --short HEAD        # must print d65690e
python tt/tt_tool.py --create-user-config
python3 -c "import json; c=json.load(open('src/user_config.json')); print(c['DESIGN_NAME'], c['VERILOG_FILES'])"   # tt_um_moein_maleki_arm16 and every src/*.v
```

- [x] **Step 2: Harden** (LibreLane 3.0.3 drives its own Docker container; the run lands in `runs/wokwi/`):

```bash
( time python tt/tt_tool.py --harden ) 2>&1 | tee scratch_pad/2026-09-06_sep/02_rtl_sprint/evidence/harden.log
bash scratch_pad/2026-09-06_sep/02_rtl_sprint/scripts/snapshot_harden.sh
python scripts/check_signoff.py runs/wokwi tt_um_moein_maleki_arm16     # must print SIGNOFF CLEAN
grep GPL-0019 runs/wokwi/28-openroad-globalplacement/openroad-globalplacement.log
```

- [x] **Step 3: Assert and record** in `REPORT.md`: built top equals `info.yaml`; tile 2x2; `CLOCK_PERIOD` 40; nine corners present with setup and hold worst slack positive; `timing__setup_vio__count` and `timing__hold_vio__count` 0; `magic__drc_error__count`, `design__lvs_error__count`, `route__drc_errors`, `route__antenna_violation__count`, `antenna__violating__nets`, `antenna__violating__pins` all 0; utilization; cell and flop counts; no `clkdlybuf` in the netlist. Read the `uio` output and input paths in `runs/wokwi/55-openroad-stapostpnr/max_ss_100C_1v60/max.rpt` by hand and record their slack.
- [x] **Step 4: If setup fails:** first raise `PL_RESIZER_SETUP_SLACK_MARGIN`, then check the negedge register-file and flag paths (they get half a period), then reduce logic depth on the reported path; never lower the clock (the pixel clock is fixed). If placement fails on density, raise `PL_TARGET_DENSITY_PCT` in steps of 5. If the design is over 72% placed utilization, apply the drop order (meter, UART receive, UART) and re-run from Task 5.
- [x] **Step 5: TinyQV's SDC (spec section 12).** After the first clean run, add `src/arm16.sdc` with the clock, `set_clock_uncertainty 2.5 -rise_from clk -fall_to clk`, `set_clock_uncertainty 2 -fall_from clk -rise_to clk`, input delay 65% max and 20% min of the period on `ui_in` and `uio_in`, output delay 65% max on `uo_out`, `uio_out`, `uio_oe` and 20% max on `uio_out[3]` (SCK), min 1 ns; reference it as `"PNR_SDC_FILE": "dir::arm16.sdc"` and `"SIGNOFF_SDC_FILE": "dir::arm16.sdc"` in `src/config.json`; re-harden; if the flow rejects the keys or the CI action strips them, keep the default constraints and record the hand-read `uio` slack instead.
- [x] **Step 6: Commit** `git commit -m "Hardened at 25 MHz: config, SDC, signoff clean"` (`runs/`, `src/user_config.json` and `src/config_merged.json` are ignored; the snapshot in `evidence/` is committed).

## Task 7: Gate-level simulation

- [~] **Step 1:**  (done once on the run-2 netlist; pending on the run-3 netlist)

```bash
source ~/oss-cad-suite/environment
export PDK_ROOT=/home/moein/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71
cp runs/wokwi/final/pnl/tt_um_moein_maleki_arm16.pnl.v test/gate_level_netlist.v
cd test && GATES=yes make -B 2>&1 | tee ../scratch_pad/2026-09-06_sep/02_rtl_sprint/evidence/gate_level_tests.log
```

The suite already samples every DUT output 20 ns after the rising edge (mid-cycle at the 40 ns period), the way logos did, so one driver serves RTL and gate level. The ROM-fed and hierarchy-poking tests skip under `GATES=yes`; the flash-fed tests, the sync-timing test, the digit-band frame test (D7), the UART tests, the delay sweep and the transaction-count test run. Expect the run to take tens of minutes; run it in the background with a Monitor on the log.
- [ ] **Step 2:** `results.xml` shows zero failures; copy it to `evidence/`.

## Task 8: Precheck, review 4, metrics

- [ ] **Step 1:** `tt/precheck` needs the TT KLayout build; if `python tt/precheck/precheck.py --gds runs/wokwi/final/gds/tt_um_moein_maleki_arm16.gds` runs in the `~/.venvs/tt-tools` environment, record its result; otherwise the CI precheck job is the gate. Codex review 4 (read-only) on `scratch_pad/.../evidence/harden_*/metrics.json`, `summary.rpt`, `src/config.json`, `src/arm16.sdc`, and `test/test.py` against spec section 14: what is unverified, what a silicon bring-up could hit.
- [ ] **Step 2: Commit** `git commit -m "Gate-level suite green on the hardened netlist; precheck and review evidence"`.

## Task 9: Push and CI watch

The user's request authorizes creating the repository and pushing. The remote `origin` is already set to `https://github.com/moein-maleki/ttsky26c-arm16.git` and the repository does not exist yet (checked with `gh repo view` on 2026-09-06). `gh` is logged in as `moein-maleki` with `repo` scope.

- [ ] **Step 1:** `gh repo create moein-maleki/ttsky26c-arm16 --public --description "arm16: a 16-bit five-stage ARM pipeline on TinyTapeout TTSKY26c"` then `git push -u origin main`.
- [ ] **Step 2:** `gh run list --repo moein-maleki/ttsky26c-arm16 --limit 10`; for each of `test`, `docs`, `gds`: `gh run watch <id> --repo moein-maleki/ttsky26c-arm16 --exit-status` (the `gds` run takes 30 to 90 minutes on the GitHub runner and includes the `precheck`, `gl_test` and `viewer` jobs). On a failure: `gh run view <id> --log-failed`, fix, commit, push, watch again. The CI `test` job uses apt Icarus (version 12) and `cocotb==2.0.1` from `test/requirements.txt`, so `tb.v` and the suite must not depend on Icarus 14 features; the `gl_test` job reruns the suite with `GATES=yes`, where D7 applies.
- [ ] **Step 3:** `gh run download <gds-run-id> -n tt_submission -n GDS_logs -n precheck_reports -D scratch_pad/2026-09-06_sep/02_rtl_sprint/evidence/ci/` and assert with warplet's `verify_submission_artifact.sh` logic (adapted for this top): `commit_id.json` commit equals the pushed SHA, `pdk.json` has PDK `sky130A` and version `8afc8346...`, metrics show positive setup and hold slack and zero violation, DRC, LVS, antenna, lint and unmapped counts, `info.yaml` in the artifact has the right top, clock and tiles, and `precheck_reports/results.xml` has no failure.
- [ ] **Step 4:** record the run URLs and the artifact assertions in `REPORT.md`. The portal submission of the 2x2 (app.tinytapeout.com, the user's account) is the user's action; the report names the commit to select.

## Task 10: Close

- [ ] `REPORT.md` (what was built, every measured number, every test with its status, deviations, what is unverified), `INFRA_AND_COMMANDS.md` complete, umbrella `README.md` index row (status hardened or submitted), memory update, `/close`.

---

## Codex review protocol (Tasks 2, 3, 4, 8)

Call `mcp__codex__codex` with `sandbox: read-only`, `approval-policy: never`, `cwd: designs/ttsky26c-arm16`, and a prompt of this shape; continue with `codex-reply` on the returned `threadId` for clarifications:

```
Review <files> against docs/spec.md sections <n> and the dialect rules in
~/.agents/skills/verilog-rewrite/references/verilog-dialect.md. Report, with file:line:
(1) functional defects (ARM semantics, pipeline hazards, handshake, reset, width),
(2) synthesis and timing risks on sky130 at 25 MHz (latches, multi-drivers, negedge paths, async paths),
(3) tests that are missing or that cannot fail (compare against spec section 14),
(4) hardening or CI risks (TinyTapeout rules: all outputs driven, uio_oe stable in reset, no clock gating).
Rank by severity. No edits.
```

Each finding is verified in the code or by a test before it is acted on (superpowers:receiving-code-review). The prompt, the response, and the disposition of each finding (fixed with commit, rejected with reason) go to `reviews/codex_review_<n>.md`.

## Verification summary (spec section 14 coverage)

| Spec item | Where |
|---|---|
| 14.1 golden model from the ARM definition | Task 1 `arm16_model.py`, `test_flags_definition`, `test_model_semantics` |
| 14.2 assembler and byte-exact check | Task 1 `arm16_asm.py`, `test_encode_known_words`, `test_cross_check_binutils` |
| 14.3 flash and PSRAM behavioural models | Task 4 `qspi_models.py` |
| 14.4 directed per class, regressions, random differential, UART loopback, ROM boot, hardware view, sync timing, frame capture, demo end to end, transaction count, delay sweep, negative test | Tasks 2, 3, 4, 5 |
| 14.5 hardening closes at 25 MHz, nine corners, snapshot | Task 6 |
| 14.6 gate-level suite | Task 7 |
| 14.7 CI green | Task 9 |

## QSPI engine and fetch sequencer design (Task 4 contract)

### Engine: lanes, orders, constants

- Command bits go MSB first on SD0 only (EBh = 1110 1011, 38h = 0011 1000) with `sd_oe = 0001`. Address nibbles A23-20 first: `0, 0, A[15:12], A[11:8], A[7:4], A[3:0]` with `sd_oe = 1111` (the 16-bit CPU address zero-extended to 24 bits; the datapath clears bit 15 for the PSRAM). Mode byte M7-0 = FFh as nibbles F, F (M5-4 = 11 keeps continuous read off, the flash always expects a command next). `sd_oe` drops at the tick after the last driven nibble, before any dummy or wait period.
- Idle: SCK low, both chip selects high, `sd_oe = 0000`, `sd_out` holds its last transmitted value (the crosstalk lesson). CS_RAM_B is constant 1.
- Byte order: both chips return bytes in ascending address order, high nibble first. Capture n (0-based) lands in nibble lane `n ^ 1` of R (lane i = bits [4i+3:4i]); 8 captures give the little-endian 32-bit instruction, 4 captures give the 16-bit word `{byte(A+1), byte(A)}` in R[15:0]. The 38h payload is `{wdata[7:4], wdata[3:0], wdata[15:12], wdata[11:8]}`.
- Internal state: local `present_state`/`next_state` (E_IDLE with the CS-high gap, E_CMD 8 periods, E_ADDR 6, E_MODE 2 flash only, E_DUMMY 4 flash read / 6 PSRAM read / 0 write, E_DATA, E_STOP waits for the capture delay line to empty then raises CS); the tick toggle flop (`tick_r` when it reads 0, `tick_f` when 1); `sck_reg` in the posedge domain and one `negedge clk` flop copying it to `sck_out` (SD changes on `tick_f` posedges, SCK edges reach the pad 20 ns later, so the chip sees 60 ns setup and 20 ns hold on every rising edge); a 48-bit transmit shift register; the 32-bit receive register R with per-lane enables; `req_cnt` 0..8 (falling edges launched for the current word); `nib_cnt`; `word_full`; a 3-stage capture-request delay line; `cs_low_cnt` (8 bits, forces CS_RAM high at `CS_LOW_MAX = 150` = 6 us, pulses `data_done` so the pipeline never hangs, sets `fault_out`); `gap_cnt`; transaction `kind`.

| Transaction | Chip | SCK periods | Notes |
|---|---|---|---|
| Stream start at A | flash | 8 + 6 + 2 + 4 = 20 preamble, then 8 per word | CS low at a `tick_f` together with command bit 7; first word complete 28 periods plus the strap after start |
| Next stream word | flash | 8 | no address, no gap; the flash auto-increments |
| Stream stop or abort | flash | 0 to 1 | if `sck_reg` is high let the falling edge complete, then CS high at the next posedge; clear the delay line, `word_full`, counters; then `GAP_CYCLES` = 2 core clocks (80 ns covers tSHSL 10 ns and tCPH 18 ns) |
| PSRAM read | RAM A | 8 + 6 + 6 + 4 = 24 | `data_done` at the fourth capture; CS high the posedge after |
| PSRAM write | RAM A | 8 + 6 + 4 = 18 | no wait; CS high at the `tick_r` after the last falling edge; `data_done` then |
| Flash literal read | flash | 8 + 6 + 2 + 4 + 4 = 24 | the controller stops the stream first, runs it, then restarts the stream at `fetch_addr` |

SCK gating (D4): at every `tick_r` the engine launches a rising edge only in a clocked phase and not when `req_cnt == 8 && !word_room_in`. `word_take_in` clears `word_full`, `nib_cnt` and (when `req_cnt == 8`) `req_cnt`; requests already in flight for the following word keep their count.

### Timing table (posedges at 0, 40, 80 ns; transaction starts at a `tick_f` at t = 0)

| t (ns) | edge | engine | SCK pad | SD pad | chip |
|---|---|---|---|---|---|
| 0 | rise, tick_f | `cs_flash_n <= 0`, `sd_out[0] <= cmd[7]`, `sd_oe <= 0001` | 0 | cmd[7] | sees CS low at R/2 |
| 20 | fall | negedge flop copies `sck_reg` = 0 | 0 | cmd[7] | |
| 40 | rise, tick_r | `sck_reg <= 1` | 0 | cmd[7] | |
| 60 | fall | | rises (edge 0) | cmd[7] | samples cmd[7]: 60 ns setup |
| 80 | rise, tick_f | `sck_reg <= 0`, `sd_out[0] <= cmd[6]` | 1 | cmd[6] | 20 ns hold from edge 0 |
| 100 | fall | | falls | cmd[6] | |
| 120 | rise, tick_r | `sck_reg <= 1` | 0 | cmd[6] | |
| 140 | fall | | rises (edge 1) | cmd[6] | samples cmd[6] |

Data nibble n of the first stream word belongs to period 20 + n. With t_f the pad time of the falling edge that clocks it out, the nibble reaches our flop at t_f + R + 6 (usable from t_f + R + 9) and stays until t_f + 81.5 + R. Strap s samples at t_f - 20 + 40 s (D9): strap 1 passes for R up to 11 ns, strap 2 for 0 to 40 ns, strap 3 for R from 20 ns.

### Controller states (`arm16_controller`, literal `present_state`/`next_state`)

States `S_IDLE` (reset), `S_ROM`, `S_STREAM_EMPTY` (D empty), `S_STREAM_FULL` (D valid), `S_DATA`. Internal nets in the output-decode block: `fetch_ready = !hazard_in && !mem_busy_out`, `fetch_accept = (present_state is S_STREAM_FULL or S_ROM) && fetch_ready && !redirect_in`.

| From | Condition (priority order) | To | Actions |
|---|---|---|---|
| S_IDLE | `rom_mode_in` | S_ROM | never leaves |
| S_IDLE | `redirect_in` | S_IDLE | `fetch_addr_load` (idempotent) |
| S_IDLE | `mem_access_in && !busy_in` | S_DATA | `data_start`, `addr_sel = 1`, `data_flash`, `data_write` |
| S_IDLE | `!busy_in` | S_STREAM_EMPTY | `stream_start` at `fetch_addr` |
| S_STREAM_* | `redirect_in` | S_IDLE | `stream_stop`, `fetch_addr_load`, `if_id_bubble`, `id_ex_bubble`; D dropped |
| S_STREAM_* | `mem_access_in` | S_IDLE | `stream_stop`; D dropped; `mem_busy` already 1 |
| S_STREAM_EMPTY | `word_valid_in` | S_STREAM_FULL | `word_take`, `fetch_word_load` |
| S_STREAM_FULL | `fetch_ready && word_valid_in` | S_STREAM_FULL | accept and refill: `fetch_addr_inc`, `if_id_load`, `word_take`, `fetch_word_load` |
| S_STREAM_FULL | `fetch_ready && !word_valid_in` | S_STREAM_EMPTY | `fetch_addr_inc`, `if_id_load` |
| S_STREAM_FULL | `!fetch_ready` | S_STREAM_FULL | hold D; the engine self-gates when R also fills |
| S_DATA | `data_done_in` | S_IDLE | `mem_busy_out = 0` that cycle so the MEM stage advances with `rdata[15:0]` |

Output decode, defaults first: every command 0, `addr_sel = 0`, `mem_busy_out = mem_access_in && !(present_state == S_DATA && data_done_in)`, `if_id_bubble = (fetch_ready && no word presented) || redirect_in`, `id_ex_bubble = hazard_in || redirect_in`, `fetch_src_rom = 0`. S_ROM: `fetch_src_rom = 1`, `if_id_load = fetch_ready && !redirect_in`, `fetch_addr_inc = if_id_load`, and a Pmod access completes in one cycle (`mem_busy_out = 0`, data undefined) so a defective engine can never touch this mode; the engine is never started (chip selects high, SCK low, `sd_oe = 0000`). S_STREAM_FULL: `word_room = fetch_ready`; S_STREAM_EMPTY: `word_room = 1`; both: `word_take = word_valid_in && word_room`. `data_flash_out = addr_is_flash_in`, `data_write_out = mem_write_in`. `redirect_in` is a level while the branch sits in EX; every redirect action is idempotent.

Invariant for the reviewer and the tests: `fetch_addr` changes only by `fetch_addr_load` (redirect) or by `fetch_addr_inc = fetch_accept`, never on `word_valid_in`; the restart address is always `fetch_addr` (D3).

### Datapath registers for this block

`fetch_addr[15:0]` (reset 0); D `fetch_word[31:0]`; the strap latches `rx_delay[1:0]` (0 treated as 1), `rom_mode`, `fwd_en` loaded from `ui_in` while `rst` is high; IF/ID as in the pipeline section; `mem_access` and `addr_is_flash` decoded from EX/MEM; the engine address mux `addr_sel ? {addr_is_flash ? alu_result[15] : 1'b0, alu_result[14:0]} : fetch_addr`.

### Verification (test/qspi_models.py and test/test.py)

- Harness: `test/tb.v` adds nets `qspi_sck = uio_out[3]`, `cs_flash_n = uio_out[0]`, `cs_ram_n = uio_out[6]`, `sd_out = {uio_out[5], uio_out[4], uio_out[2], uio_out[1]}`, `sd_oe = {uio_oe[5], uio_oe[4], uio_oe[2], uio_oe[1]}`; timescale 1 ns / 1 ps in `tb.v` so 1.5 ns delays exist; `Clock(dut.clk, 40, unit="ns")`, one clock per test; a `QspiBus` helper composes `uio_in` from whichever model is selected.
- Model timing is ns-level. Forward path: the models sample `sd_out` on `RisingEdge(qspi_sck)` and re-read it 5 ns before and after the edge (any change fails: same-edge launch check). Return path: on each SCK falling edge while selected, `Timer(R + 1.5)` then drive `x` on the four lanes, `Timer` to `R + 6` then drive the nibble; R is a parameter swept 0 to 40 ns in 5 ns steps. The `x` window is what makes the sweep honest. At gate level the same models work because they key on pin edges; add a 1 ns settle before reading lanes at an edge.
- `FlashModel` (W25Q128JV): on CS falling (SCK must be low) count periods; 0 to 7 collect SD0 and require EBh; 8 to 13 the address MSB first; 14 to 15 the mode byte (M5-4 == 10 fails: continuous read must never be armed); 16 to 19 dummies with `sd_oe` required 0; from the falling edge of period 19 drive bytes from the image with auto-increment until CS rises; release the lanes R/2 + 7 ns after CS rises; count transactions, bytes and first addresses; any other command, CS rising with SCK high, or a CS-high gap under 10 ns sets an error the test asserts on.
- `PsramModel` (APS6404L): EBh with 6 wait periods then data; 38h with data from period 14 (high nibble then low, stored at address++); tCEM per CS-low interval (over 8 us fails at once, the maximum is reported so the test asserts under 6 us); tCPH under 18 ns fails; 32 KB backing store; `sd_oe` must be 0 during wait and read data.
- Always-on bus monitor: never both selects low; `sd_out` unchanged while `sd_oe` is 0; `sd_oe` never 1 while a model drives; a watchdog fails if no word is accepted for 2,000 cycles outside reset and outside a data access.

Directed tests (numbers used in Task 4): 1 sequential stream (64 distinct words: accepted words equal the image in order, exactly one flash transaction of 256 bytes, `fetch_addr` visits 0, 4, 8, ... once each; R = 20, strap 2); 2 restart on branch (a taken branch every 5 words: each transaction's first address is the target, nothing past a branch is accepted, transactions = taken branches + 1); 3 data-access interleave (stream, abort, one PSRAM transaction, restart at the current PC; PSRAM transaction count equals the golden model's loads plus stores); 4 backpressure hold (force the hazard status high for 12 cycles while a word is valid: D unchanged, exactly one `if_id_load`, `fetch_addr` advances by 4 once, `word_take` fires once); 5 no double fetch after a stall (16 more words: strictly +4, flash bytes = 4 x accepted); 6 round-trip sweep (9 values of R x 3 straps, 32 words: expected strap 1 to 10 ns, strap 2 all, strap 3 from 20 ns; at least two straps correct through 30 ns); 7 PSRAM write then read back (0x1234 at 0x8010 and a second word at 0x8012; backing store holds bytes 34 12); 8 tCEM under a load-heavy program (200 loads and stores: maximum CS-low under 6 us, no fault) plus a negative sub-test forcing `word_room` low mid-read to prove the 150-cycle counter raises CS and sets `fault_out`; 9 data pins hold when idle (monitor over a whole program); 10 ROM mode bus quiet (both selects high, SCK low, data enables 0 for a whole run); 11 negative test (an inverted byte order in one image).

Order within Task 4: engine alone with the flash model and tests 1, 6, 9; then the controller handshake with tests 4 and 5; then the PSRAM path with tests 3, 7, 8; then 10 and 11; synthesize after the engine and after the controller.

### Risks and the test that catches each

1. Wrong sample point at the real 20 ns round trip: test 6 with the x window, replayed at gate level; on silicon the strap sweep of bring-up step 6.
2. Same-edge launch (the KianV bug) or SD launched on the wrong tick: the models' 5 ns setup and hold check on every SCK rising edge (test 1) and the SCK output-delay line in the SDC.
3. Nibble or byte order wrong, or the mode byte arming continuous read (every later EBh misparsed until a power cycle): tests 1 and 7 with asymmetric data; the flash model's M5-4 check on the first transaction.
4. Handshake defects (advance on valid alone, a lost word on same-cycle accept-and-refill, the wrong word dropped on abort): tests 4 and 5 and the strict +4 address monitor under every test.
5. An abort or start race that leaves a chip selected or the pipeline hung: test 3 with the watchdog and the tCEM assertion, and test 8's forced hang.

---

## Progress log

### 2026-09-06 (sprint hours 0 to 3) — Tasks 0 to 4 and 6 done, 5 partly, 7 partly; paused after Codex review 2
Commits `b92f188` (Task 0), `64e70ad` (Task 1), `0a52e6b` (Task 2), `409ba09` (Tasks 3 and 4, review 1, area),
`b46e690` (SDC, UART_EN flop, hardens 1 and 2), `a9bdd86` (review 2), `cd0f4ed` (suite green, harden 3, pause).
Task 5: the UART is cut (D13), so its tests and RTL are not written; docs done (spec v0.4, info.md).
Task 6: three hardens signoff clean; run 3 on `a9bdd86` (`evidence/harden_20260906T101958Z`).
Task 7: one replay on the run-2 netlist (`evidence/gate_level_run1_netlist2.log`, 7 pass, 4 fail on test
defects since fixed); the replay on the run-3 netlist is the next action. Task 8: reviews 1 and 2 applied
(`reviews/`); local precheck not run. Tasks 9 and 10: pending. Decisions D10 to D13 added. Next:
`bash scripts/run_gate_level.sh`, then Task 9. See `REPORT.md`.
