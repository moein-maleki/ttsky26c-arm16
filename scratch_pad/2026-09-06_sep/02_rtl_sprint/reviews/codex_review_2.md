# Codex review 2 (commit b46e690 plus the working tree, 2026-09-06)

Reviewer: Codex (GPT-5) through the MCP, read-only sandbox. Scope: the QSPI engine, the sequencer, the
memory models and flash-fed tests, the hardening evidence. Verdict quoted: "No P0 issue and no normal-path
QSPI or fetch-controller defect was found. The evidence supports 25 MHz operation with QSPI_DLY = 2 and a
20 ns multiplexer round trip. I would not approve tapeout yet." Thirteen findings.

| # | Finding (shortened) | Verified | Disposition |
|---|---|---|---|
| 1 | P1: 1,778 max-slew, 22 max-fanout, 15 max-cap violations in the signoff STA; `check_signoff.py` does not gate them; KLayout DRC off in the template config | yes (logos had 0/1/0 at 14% utilization) | open: recorded in REPORT.md with the next step (design-repair settings or a buffered freeze net); setup and hold are met with the actual slews; the TinyTapeout precheck does not gate these; KLayout DRC runs in the CI precheck |
| 2 | P1: `test_delay_sweep` leaves every iteration's model tasks alive, so several models drive `uio_in` | yes | fixed: models are stoppable (`stop()` cancels every task), `FlashRun.stop()` runs after every run and in the sweep's `finally` |
| 3 | P1: random flash programs end with `B .` before the epilogue, so the dump is unreachable | yes | fixed: `FlashRun` strips a trailing self-branch; the epilogue ends with its own |
| 4 | P1: `FallingEdge` not imported; the hard-counter test dies before testing; it never checked recovery | yes | fixed: import added; the test checks CS, SCK and the lane enables after the timeout, the 6,040 ns low time, and the model and monitor error lists |
| 5 | P2: a tCEM timeout can leave SCK high and the lanes driven; the cutoff is one cycle late (6,040 ns) | yes | fixed: the timeout clears SCK and the enables and sets stop_pending; E_GAP clears them too; the one-cycle lateness is documented (6.04 us against the 8 us limit) |
| 6 | P2: STA cannot prove the nibble window; strap 3 has 1.5 ns of hold margin at 20 ns; spec 12's "51 ns" is wrong | yes | fixed in spec 12: per-strap windows stated, strap 2 nominal (31 ns setup, 41 ns hold at 20 ns), the sweep simulation and the bring-up strap sweep named as the evidence |
| 7 | P2: the PSRAM model stores only four write nibbles and ignores the rest | yes | fixed: every clocked-in byte lands in memory (linear burst) |
| 8 | P2: `capture_band` counts HSYNC from its own coordinate; VSYNC unchecked | yes | fixed: real pin falling edges counted and positioned, pulse end checked, VSYNC high outside its pulse |
| 9 | P2: the harden snapshot's `commit_id.json` names `409ba09` while the run used later content | yes | fixed by procedure: the final harden runs on the committed state after this round |
| 10 | P3: the hold check samples once at +5 ns and ignores OE | yes | fixed: any edge on the lanes or the enables within 5 ns after the SCK rising edge is an error |
| 11 | P3: `assert ... or True` in the literal test; the init prefix moved the pool | yes | fixed: the pool address is stated (0x54) and the model's dump slots for r1 and r2 are asserted |
| 12 | P3: a data abort does not clear `d_valid` (harmless today) | yes | fixed: `if_id_bubble_out = abort` (redirect or data access) |
| 13 | P3: obsolete UART and falling-edge status-register text in spec 1, 2, 9, 12, 16 and `info.yaml` | yes | fixed |

First-review dispositions the reviewer accepted as closed: 1, 2 (scope), 4, 6, 7, 8, 9, 10, 11 (accepted), 12, 13.
Not fully closed in the reviewer's view: 3 (a gate-level result was not yet present) and 5 (coverage);
both are addressed by this round's fixes and the reruns recorded in REPORT.md.
