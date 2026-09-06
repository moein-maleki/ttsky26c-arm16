# ttsky26c-arm16

A 16-bit five-stage ARM pipeline on one TinyTapeout 2x2 tile, sky130A, shuttle TTSKY26c. Forwarding,
hazard detection, condition codes, a barrel shifter and the standard 32-bit ARM instruction encoding, with
the program streamed from an external QSPI flash and the data in a QSPI PSRAM on the TinyTapeout QSPI Pmod.
A seven-segment digit shows the program's output with no computer attached. A UART over the demo board's USB
bridge is there for debugging.

| Item | Value |
|---|---|
| Target | TinyTapeout TTSKY26c, sky130A, 2x2 tile, 25 MHz |
| Status | **spec** (spec -> rtl -> sim-clean -> hardened -> submitted) |
| Specification | `docs/spec.md` |
| Toolchain | LibreLane 3.0.3, sky130A `8afc834`, oss-cad-suite (iverilog, cocotb 2.x, yosys), see `../../toolchain/tinytapeout.md` |
| Origin | `sandbox/computer-architecture-lab` (University of Tehran architecture lab, 2022), narrowed to 16 bits |
| Deadline | 2026-09-07 20:00 UTC |

## Layout

- `docs/spec.md`: the design specification. Read it first.
- `docs/info.md`: the TinyTapeout datasheet page.
- `src/`: RTL (not yet written; the template placeholder is in place).
- `test/`: cocotb tests.
- `scratch_pad/`: dated session work folders with plans, reports, evidence and scripts. `PROVENANCE.md` records
  what was promoted from the lab repository.
- `tasks/`: `todo.md`, `lessons.md`, and the generated `STATE.md` board.
- `handoff/`: session handoff notes.
- `tt/`: a local clone of `TinyTapeout/tt-support-tools` at commit `d65690e` (the pin that hardened logos), ignored by git; CI fetches its own copy through `tt-gds-action@ttsky26c`.

## Working in this repository

```bash
git clone https://github.com/TinyTapeout/tt-support-tools tt && git -C tt checkout d65690e   # once, local only
source ~/oss-cad-suite/environment
cd test && make -B                 # RTL simulation
source ~/.venvs/librelane/bin/activate && export PDK_ROOT=~/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71
./tt/tt_tool.py --create-user-config && ./tt/tt_tool.py --harden          # local hardening
```
