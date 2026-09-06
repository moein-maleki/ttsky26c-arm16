# Planning review, risk-first (2026-09-06)

## Probe defects found beyond the known list

1. The fetch interface must be valid/ready with backpressure: IF_stage_reg loads instruction_in every
   non-frozen cycle with no ready qualifier; IF_stage re-requests the same PC after any freeze; the streaming
   controller pulses ready for one cycle, so a word delivered during a freeze is fetched again after a full
   restart and executed twice.
2. The flush and reset bubble is 0x00000000 = ANDEQ r0, r0, r0 with wb_en = 1: value-neutral, but once any
   CMP sets Z every bubble asserts a write to r0, trips the hazard unit with FWD_EN low, miscounts retired
   instructions, and lights the hardware view. A bubble must carry condition 0b1111 or a valid bit.
3. FWD_EN is combinationally live in hazard_detection.v and forwarding_unit.v; a change between decode and
   execute gives a wrong operand. Latch it in reset.
4. Reset styles are mixed (IF_stage_reg, ID_stage_reg, IF_stage synchronous; EXE_stage_reg, MEM_stage_reg,
   status_register asynchronous; register_file none plus a simulation-only initial). One style.
5. MEM_stage.v still subtracts the lab's 1024 data base and drops address bit 0.

## v0.2 for TTSKY26c: fold in or park

| | Candidate | Decision | Reason |
|---|---|---|---|
| a | State the drain policy | fold in (mandatory) | a defect fix; the simpler stall logic; 30% faster on loops and loads; removes the duplicate instruction copy |
| b | Self-armed continuous read | park | needs a mode-aware flash model and an FFh Continuous Read Mode Reset after every chip reset (rst_n does not reset the flash; otherwise the first command is taken as an address); a failure with no on-chip signature |
| c | Resolve unconditional branches at decode | park | saves 1 cycle of about 56; a second PC-mux and flush source; only ROM mode exercises the priority case |
| d | Keep forwarding; note where it is live | fold in | 64 cells, 0.9%, lab-verified; live in ROM mode; latch FWD_EN at reset; fix the pipeline-study claim |
| e | Memory clock 1:1 | park | with SCK = 40 ns the return-data window at the input runs 29 ns (20 mux + 6 tCLQV + 3 setup) to 61.5 ns (next SCK fall + 1.5 tCLQX) after launch; the only core edge inside is 40 ns, so QSPI_DLY has exactly one legal setting. At core/2 the window is 29 to 101.5 ns and delays 1 and 2 are both legal; if the mux is 30 ns rather than 20, delay 2 still has 31 ns margin. Also needs a glitch-free gated clock on an output pad, which this flow has never produced |
| f | 1-entry branch-target cache | park | 11% on loops assuming continuous read; about 3.5% of the tile; a second fetch entry point in the riskiest block |
| g | Combinational 16-instruction ROM | fold in, promote to Must above the UART | the only mode with nothing on the memory socket; the proof of life; the only mode at one instruction per cycle; DJ8 precedent; 1 to 2% (measure); the UART needs a host and shows a stranger nothing; TinyQV's only silicon bug was its UART RX |

Area after the fold-ins: about 72 to 73%, on the cap. Drop order if the rewrite's 5% does not appear:
CYCLES/RETIRED, then the UART. The ROM is not droppable. 72% target, 74.6% proven line.

RTL rules: valid/ready fetch, address advances once per accepted word; a data access or redirect aborts the
fetch in flight, the fetch address register is the single source of truth; bubble = valid bit or condition
0b1111; ROM-mode isolation (controller idle, selects high, SCK low, data pins inputs; the hardware view must
not depend on the controller); ROM program with no loads, registers written before read, unused entries B .,
nested delay loops; X-containment (no control signal depends on unreset register data unless a decoded bit
already qualifies it); one reset style; exactly one bus transaction per load or store, counted by the model.

## v2 ranked by risk

Track decision first: tnt's macro, the ROM macro and latch density are sky130-only; the SRAM cache is
IHP-only; a 3x2 sky130 tile (108,850 um^2) takes v0.2 at about 47% with room for a synthesized ROM, a loop
buffer and a BTC without any hard macro.

1. tnt rf_top (highest): license unresolved; PDN checked with relaxed rules, a floating tap is a dead register
   file invisible in simulation (black box); nine-corner libs; LVS with hand-drawn cells. Detection: precheck,
   LVS, the PDN connectivity report read by hand, IR drop, model equivalence against FemtoRV's netlist.
   Mitigation: a flop register file hardened as a second candidate. Value only with a 32-bit datapath.
2. Emulator data channel (high): firmware that does not exist for the RP2350; VGA to one bit per colour;
   timing through the mux at the project clock with no precedent on this board. Detection only on the board.
   Mitigation: keep the PSRAM path behind a strap; treat as research.
3. ROM-macro program (medium-high, bounded): uninvestigated generator; contents frozen; hard-macro PDN and LVS.
   Detection: extract the ROM contents back out of the GDS and compare with the hex; gate-level with the model;
   a "program frozen" review 48 hours before the deadline. Mitigation: the flash path remains; measure a
   synthesized ROM first (below about 64 instructions it is probably the same area band at zero integration risk).
4. Latch loop buffer (medium): a glitch on a latch enable writes garbage; STA is pessimistic on latch paths,
   which pushes a first-time designer to waive violations. Detection: gate-level with SDF at the slow corner,
   a structural check on every latch enable, a write-spacing property. Mitigation: an enable strap, default off.
5. Clock forwarding (medium with a strap, high without): the one-period window; a plain AND gating the clock
   glitches, so use the integrated clock-gate cell or a falling-edge enable, and CTS must treat the net as a
   clock; TinyQV's crosstalk is milder at 25 MHz, not absent. Detection: a bench with the mux as explicit
   10 ns delays swept 0 to 40 ns; STA on the clock output path; SDF. Mitigation: a reset-time strap for the
   ratio (1:1 or 1:2). Alternative: 50 MHz core, SCK = core/2, pipeline clock-enabled every other cycle under
   a multicycle constraint (failure mode: a wrong SDC, silent under STA). Precedent: Whisk.
6. Continuous read (low-medium): mode disagreement after a chip reset; the FFh reset (8 clocks, all four
   lines high) before the first command, as RP2040 boot2 does. Detection: a mode-aware model, one boot against
   a pre-armed and one against a cold model; a "full command after reset" property. Mitigation: re-send the
   full command after every data access and skip it only on branch restarts; or a strap.
7. Branch-target cache (low): key on the full target; the controller restarts at target + 4; reset clears the
   entry; ROM-mode contents must not hit in flash mode. Detection: the golden-model differential.
8. Decode-stage branches: skip.

Verification each needs: rf_top (model vs FemtoRV netlist; PDN and LVS by hand; FemtoRV precedent);
emulator (protocol model from the PIO source; RP2040 board only); ROM macro (generator model; GDS extraction;
gate-level with the model); latch buffer (write-spacing and enable-structure properties; SDF at slow corner);
clock forwarding (mux delay swept; STA on the clock path; SDF; Whisk); continuous read (mode-aware model cold
and pre-armed; the reset property; FazyRV, FFD16, boot2); BTC (differential; cover on hit and miss).

Recommended v2 on the IHP track: the SRAM cache, continuous read with the FFh reset, a strappable SCK ratio.
On sky130 26d: a 3x2 tile, a ROM sized by the v0.2 measurement (synthesized unless above about 64
instructions), continuous read, a strappable ratio, the latch buffer only behind a strap; rf_top only with a
license and only to enable a 32-bit datapath.

## The single biggest risk to the current chip

The QSPI path end to end: a controller not yet written, replacing a probe with four confirmed defects,
through a mux whose 20 ns round trip was measured on one die at room temperature, into a flash whose
quad-enable bit must be set by hand once, beside a PSRAM with an 8 us select limit, with no observability on
silicon beyond a blue background and four PC digits. nanoV capped at 18 MHz by its sampling edge, KianV
shipped the same-edge launch, TinyQV lost weeks to mux crosstalk. Area and timing are detected before
tapeout; a QSPI defect is detected in March 2027. In order: build the controller from TinyQV's proven
structure; keep SCK at core/2 with the strap; edge-accurate models with the mux swept 0 to 40 ns (pass: two
settings work to 30 ns); the transaction-count check, the random differential, one negative test that must
fail; the gate-level replay with the uio slack read by hand; the ROM as the isolated insurance and the first
thing verified; the bring-up steps written into docs/info.md.

## Order of work for the 36 hours, with kill criteria

1. Hours 0-8: pipeline with drain, valid/ready fetch, bubbles, the ARM-standard fixes, the ALU flags; golden
   model and encoder in parallel. Gate: directed tests pass with flags.
2. Hours 8-14: ROM mode, VGA, peripheral decode, hardware view. Gate: the counting demo renders a frame from
   the ROM with the QSPI idle. The minimum shippable chip.
3. Hours 14-26: the controller, the edge-accurate models, the mux sweep, the random differential. Gate: the
   demo runs from the flash model at every strap setting.
4. Hours 26-32: UART if area allows, synthesis after each block, harden, nine corners, gate-level replay.
   Kill criterion: at hour 30, if the controller has not passed step 3, ship with the ROM verified and the
   controller marked unverified in the datasheet.
5. Hours 32-36: CI, submission, snapshots.
