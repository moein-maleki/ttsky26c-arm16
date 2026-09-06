# ttsky26c-arm16

A 16-bit five-stage ARM pipeline on one TinyTapeout 2x2 tile, sky130A, shuttle TTSKY26c. Forwarding,
hazard detection, condition codes, a barrel shifter and the standard 32-bit ARM instruction encoding, with
the program streamed from an external QSPI flash and the data in a QSPI PSRAM on the TinyTapeout QSPI Pmod.
A monitor on the TinyVGA Pmod shows the program's output as four large digits with no computer attached. An
internal demo ROM runs with nothing on the memory socket. The UART of the first specification was cut for area.

| Item | Value |
|---|---|
| Target | TinyTapeout TTSKY26c, sky130A, 2x2 tile, 25 MHz |
| Status | **submitted** (spec -> rtl -> sim-clean -> hardened -> submitted): Tiny Tapeout SKY 26c, 2026-09-06, commit `42ba458`, [gds run 34044878215](https://github.com/moein-maleki/ttsky26c-arm16/actions/runs/34044878215) |
| Specification | `docs/spec.md` (v0.4; section 19 records the implementation decisions) |
| Results | 74.99% of the 2x2 tile placed, setup slack +6.87 ns and hold +0.108 ns at 25 MHz over nine corners, DRC, LVS and antenna clean, precheck 15 of 15; 44 pytest, 52 cocotb tests (51 pass, 1 skip), 11 of 11 runnable tests pass on the hardened netlist |
| Report | `scratch_pad/2026-09-06_sep/02_rtl_sprint/REPORT.md` |
| Toolchain | LibreLane 3.0.3, sky130A `8afc834`, oss-cad-suite (iverilog, cocotb 2.x, yosys), see `../../toolchain/tinytapeout.md` |
| Origin | `sandbox/computer-architecture-lab` (University of Tehran architecture lab, 2022), narrowed to 16 bits |
| Silicon | chips projected 2027-03-27; GDS viewer at https://moein-maleki.github.io/ttsky26c-arm16/ |

## Layout

- `docs/spec.md`: the design specification. Read it first.
- `docs/info.md`: the TinyTapeout datasheet page.
- `src/`: the RTL in the verilog-rewrite dialect: a structural top, `arm16_controller` (fetch, bus and pipeline-flow sequencer), `arm16_datapath` (the five stages, register file, ALU, shifter, peripherals) and the units (`qspi_master`, `vga_renderer`, `demo_rom`, decoder, hazard and forwarding units); `arm16.sdc` and `config.json` for hardening.
- `test/`: the software testbench (`arm16_asm.py` encoder, image builder and dump epilogue; `arm16_model.py` golden model; `programs.py`; `test_software.py`) and the hardware testbench (`tb.v`, `test.py` cocotb suite, `qspi_models.py` flash and PSRAM models, `vga_capture.py` reference render).
- `scratch_pad/`: dated session work folders with plans, reports, evidence and scripts. `PROVENANCE.md` records
  what was promoted from the lab repository.
- `tasks/`: `todo.md`, `lessons.md`, and the generated `STATE.md` board.
- `handoff/`: session handoff notes.
- `tt/`: a local clone of `TinyTapeout/tt-support-tools` at commit `d65690e` (the pin that hardened logos), ignored by git; CI fetches its own copy through `tt-gds-action@ttsky26c`.

## Working in this repository

```bash
git clone https://github.com/TinyTapeout/tt-support-tools tt && git -C tt checkout d65690e   # once, local only
source ~/oss-cad-suite/environment
cd test && python3 -m pytest test_software.py -q   # software testbench
cd test && make -B                 # RTL simulation (ROMTEST=no for the shipped ROM; GATES=yes on test/gate_level_netlist.v)
source ~/.venvs/librelane/bin/activate && export PDK_ROOT=~/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71
./tt/tt_tool.py --create-user-config && ./tt/tt_tool.py --harden          # local hardening
```
