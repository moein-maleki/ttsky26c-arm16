# arm16 design specification

> Version 0.3, 2026-09-06. Status: agreed, RTL may start. Change from 0.2: the stall policy is stated
> (drain), the fetch interface is valid/ready, forwarding is documented as live only in ROM mode, the
> internal ROM outranks the UART, the controller tick is parameterized, the counters become one meter.
> Change from 0.1: the TinyVGA Pmod replaces the seven-segment digit, the UART sits behind the mode switch,
> the clock is fixed at 25 MHz.
> Target: TinyTapeout shuttle TTSKY26c, sky130A, one 2x2 tile, deadline 2026-09-07 20:00 UTC.
> Author: Moein Maleki. Written in Simplified Technical English.

## 1. Purpose

arm16 is a small ARM processor. It fetches its program from an external flash chip and keeps its data in an
external RAM chip. It shows what it does on a monitor through the TinyVGA Pmod. It talks to a computer
over a serial link when you ask it to.

The purpose of the chip is fixed. The user must learn the full flow from RTL to GDSII, and the chip must
work. A stranger must be able to watch it work in ten seconds with no computer attached. Every decision in
this document follows that rule. Novelty is not a goal.

Two facts from the TinyTapeout project index give the chip its story. No ARM core has ever been taped out on
TinyTapeout. No pipelined CPU that fetches from external serial memory has been taped out there either.

## 2. Summary

| Item | Value |
|---|---|
| Architecture | Five-stage ARM pipeline from the University of Tehran architecture lab (2022) |
| Instruction encoding | 32-bit ARM, a subset of ARMv4, standard field layout |
| Datapath | 16 bits: registers, ALU, shifter, addresses, memory words |
| Registers | r0 to r14, 16 bits each; r15 is the program counter |
| Program memory | 32 KB of the external QSPI flash, read-only, streamed |
| Data memory | 32 KB of the external QSPI PSRAM |
| Peripherals | VGA output of a 16-bit value as four large digits, switch input, UART, a retired-per-frame meter |
| Core clock | 25 MHz, set by the demo board; it is also the VGA pixel clock, so it is fixed |
| Memory clock | 12.5 MHz, half the core clock |
| Expected speed | 16 core cycles per instruction in straight-line code, about 34 on loop-heavy and 48 on load-heavy code (cycle model, section 13) |
| Tile | 2x2, about 72,565 um^2 usable; target utilization at most 72% |

## 3. Features included

### 3.1 Instruction set

The processor decodes the 32-bit ARM instruction format. It executes the subset below. The encoding of every
supported instruction is the standard ARM encoding, so a standard assembler produces correct code for it.

| Class | Instructions | Notes |
|---|---|---|
| Data processing | MOV, MVN, ADD, ADC, SUB, SBC, AND, ORR, EOR, CMP, TST | S bit updates N, Z, C, V |
| Operand 2, immediate | 8-bit value rotated right by 2 x rot | rotation is in a 16-bit ring; every 16-bit constant a standard assembler can encode gives the same value here |
| Operand 2, register | Rm shifted by a 5-bit immediate: LSL, LSR, ASR, ROR | |
| Load, store | LDR, STR | 16-bit word, address = Rn + or - 12-bit immediate, pre-indexed, no writeback |
| Branch | B, BL | target = PC + 8 + (imm24 << 2); BL writes r14 = PC + 4 |
| Return | MOV pc, lr and any data-processing write to r15 | branches to the result |
| Program counter read | Rn or Rm = r15 reads PC + 8 | allows LDR from a literal pool and ADR |
| Conditions | EQ, NE, CS, CC, MI, PL, VS, VC, HI, LS, GE, LT, GT, LE, AL | applied to every instruction; 0b1111 never executes |
| Unsupported opcodes | RSB, RSC, TEQ, CMN, BIC, and every mode-11 encoding | execute as NOP: no write, no flag change |

Flags follow the ARM definition. N is bit 15 of the result. Z is set when the result is zero. C is the
carry out of bit 15 on addition and NOT borrow on subtraction. V is signed overflow of the 16-bit result.
CMP and TST always update the flags. LDR, STR and B never update the flags.

### 3.2 Pipeline

Five stages: fetch, decode, execute, memory, write-back. Forwarding from the memory and write-back stages
into execute. Hazard detection stalls one cycle on a load-use dependency when forwarding is on, and stalls
on every read-after-write dependency when forwarding is off. A switch, latched at reset, selects forwarding
on or off, so the two behaviours can be compared on silicon. A taken branch is resolved in execute and
removes the two younger instructions. There is no branch prediction and no delay slot. The register file
and the status register write on the falling clock edge, as in the lab design.

**Stall policy: drain.** When the fetch stage has no instruction ready it passes a bubble to decode and
the older instructions continue. The pipeline holds only for a data access in the memory stage or a hazard
stall. A taken branch or a write to r15 discards the fetch in flight and any buffered word before the
restart. A bubble carries condition 0b1111 and never an all-zero word. The fetch interface is valid/ready
with backpressure: the controller holds a delivered word until the pipeline accepts it, and the fetch
address advances exactly once per accepted word.

**Where forwarding is live.** Forwarding and the load-use stall act only when instructions enter execute
on consecutive cycles, which happens in ROM mode. On the streamed path each instruction retires before the
next is decoded, so FWD_EN changes nothing there. The cycle model (section 13) puts the drain policy 30%
ahead of holding all stages on loop-heavy and load-heavy code; forwarding costs 64 cells, under 1% of the
tile, and is kept for the ROM path where it is worth 40 to 80%.

### 3.3 Memory system

One QSPI controller serves instruction fetch and data access over the shared Pmod bus.

- Instruction fetch streams. The controller holds the flash chip select low and keeps the clock running
  while the program counter advances in sequence. A sequential 32-bit instruction costs 8 memory clocks.
  A taken branch aborts the stream and restarts it at the target, which costs 20 memory clocks of setup.
- The controller always has the next sequential instruction in flight. There is no larger buffer.
- The controller advances on a memory-clock tick whose ratio to the core clock is a parameter, 2 in this
  version, and it takes the sampling strap as an integer, so a 1:1 memory clock later is a change inside
  the controller only.
- A data access interrupts the instruction stream. The controller finishes the data access, then restarts
  the instruction stream at the current program counter.
- Reads use command EBh in single-command, quad-address, quad-data form on both chips. Writes use command
  38h on the PSRAM. No volatile chip mode is ever set. The chip boots from a cold Pmod.
- The PSRAM chip select is never held low for longer than 6 us. A hard counter enforces it.
- The receive sampling point is one full memory clock after the launch edge, plus a delay of 1 to 3 core
  clocks set by two input pins while reset is active.
- The memory clock is launched on the falling core edge, so data leads the clock by half a core cycle.
- Data output pins hold their last value when the controller is idle.

### 3.4 Peripherals

All peripheral registers are 16 bits wide at even addresses in the top 256 bytes of the address space.
Peripheral accesses take one cycle and do not touch the Pmod bus.

| Address | Name | Access | Function |
|---|---|---|---|
| 0xFF00 | VGA_VAL | read, write | the 16-bit value shown on the screen as four hexadecimal digits |
| 0xFF02 | SW | read | bits [7:0] are the eight input pins |
| 0xFF04 | UART_DATA | read, write | write sends one byte; read returns the received byte and clears RX_VALID |
| 0xFF06 | UART_STAT | read | bit 0 TX_BUSY, bit 1 RX_VALID, bit 2 RX_OVERRUN |
| 0xFF08 | UART_DIV | read, write | core clocks per bit; reset value 217 gives 115,200 baud at 25 MHz |
| 0xFF0C | METER | read | instructions retired during the previous video frame, 16 bits, latched at vertical sync (optional feature, see section 11) |

| 0xFF10 | VGA_FG | read, write | bits [5:0] foreground colour, two bits each of red, green and blue; reset white |
| 0xFF12 | VGA_BG | read, write | bits [5:0] background colour; reset black |

Reads of unmapped addresses return 0. Writes to unmapped addresses do nothing.

The video output is 640 by 480 pixels at 60 Hz through the TinyVGA Pmod, two bits per colour. The program
does not draw pixels. A hardware renderer paints VGA_VAL as four large seven-segment style hexadecimal
digits across the middle of the screen, each segment a block of 32 by 32 pixels, in the foreground colour on
the background colour. Nothing is stored except the three registers; the picture is computed as the beam
sweeps. Measured cost on sky130: 306 cells and 59 flip-flops including the timing generator
(`scratch_pad/2026-09-04_sep/06_vga_question/`).

The UART is 8 data bits, no parity, one stop bit. It has one transmit holding byte and one receive holding
byte. RX_OVERRUN is set when a byte arrives while RX_VALID is set; it clears when UART_DATA is read.

### 3.5 Internal demo ROM

When the BOOT_ROM pin is high at reset, the processor fetches addresses 0x0000 to 0x003F from a 16-instruction
ROM inside the chip instead of the flash. The ROM holds a program of about 15 instructions that counts on the screen through VGA_VAL: registers
written before they are read, an eight-deep dependent chain in the loop so that the count rate changes
about 2x with FWD_EN, no loads, and unused entries that branch to themselves. In ROM mode the QSPI
controller is held idle with both chip selects high and the data pins as inputs, so a defective controller
cannot affect this mode. It is the proof of life if the Pmod path fails on silicon and the only mode in
which the pipeline runs at one instruction per cycle. It is a must-have (section 11).

### 3.6 Display views

A switch selects what the screen shows.

- Program view: VGA_VAL in the program's colours.
- Hardware view: the program counter as the four digits, white on black, and the background turns dark
  blue while the QSPI bus is active. This view works even when the program is wrong. With USER high the
  hardware view shows the meter instead of the program counter, if the meter is built.

## 4. Features excluded

| Feature | Why it is out |
|---|---|
| Cache | sky130 has no SRAM macro; a flop cache of 4 lines costs 14% of the tile and 128 instructions about 400% (measured, `scratch_pad/2026-09-04_sep/05_cache_question/`). Planned as arm16 v2 on a later IHP shuttle with the SG13G2 512x16 single-port macro on a 3x2 tile |
| 32-bit datapath | the 32-bit register file alone exceeds the tile budget |
| Thumb or any 16-bit encoding | a scope change against the agreed brief; noted as future work |
| Multiply, LDM/STM, byte loads and stores, halfword forms, SWP, MRS/MSR, SWI, coprocessor | not in the lab core; each adds decode and test surface with no demo value |
| Register-specified shifts, post-indexing, writeback, register offsets | not in the lab core; the assembler must not emit them |
| LDR to r15 | not supported; return with MOV pc, lr |
| Interrupts, exceptions, processor modes, banked registers | not in the lab core |
| Execution from PSRAM | the PSRAM needs its chip select raised every 8 us; the flash has no such limit |
| Second PSRAM chip | its select pin is held high; 32 KB of data is enough |
| Continuous-read and QPI chip modes | volatile; would make boot depend on an init sequence |
| Reset of the general registers | ARM leaves them unpredictable at reset; a reset costs about 2.5% of the tile |
| On-chip flash programming | the flasher tool writes the flash through the demo board |
| Framebuffer, text mode, sprites | no memory for a frame on the tile; streaming pixels from the PSRAM would take the bus from instruction fetch for the whole visible frame |
| The demo board's seven-segment digit | it shares the eight output pins with the VGA Pmod; its jumpers are cut |
| Branch prediction | the cost of a taken branch is the stream restart, which no predictor removes |
| Self-armed continuous read | 14% on loop-heavy code in the model; needs an FFh mode reset after every chip reset because reset does not reset the flash; follow-on chip |
| Memory clock equal to the core clock | 2x on everything in the model; at 25 MHz the return-data window admits exactly one sampling-strap setting, and the clock must be forwarded to a pad; follow-on chip with a strappable ratio |
| Branch-target cache | one entry costs about 3.5% of the tile for 11% on loop-heavy code; follow-on chip |
| Branch resolution in decode | under 2%; skipped |
| Latch loop buffer | 6 to 12% of the tile for 4 to 8 instructions; no room beside the VGA and UART |
| ROM macro holding a demo program | 1.51 bits per um^2, 256 instructions in 7.5% of the tile, runs at one instruction per cycle; toolchain not yet investigated; follow-on chip |
| A parallel data path to the demo board's microcontroller | needs two outputs the VGA holds and firmware nobody has ported to the RP2350 board; follow-on chip |
| A second memory port, DTR reads | none proven on TinyTapeout |

## 5. Changes from the lab core

| Item | Lab core | arm16 | Reason |
|---|---|---|---|
| Datapath width | 32 bits | 16 bits | area |
| Instruction memory | ROM inside the fetch stage | streamed from external flash | area, real programs |
| Data memory | cache plus asynchronous SRAM | external QSPI PSRAM | area, board has no SRAM |
| Branch offset | bytes from PC + 4, unshifted | words from PC + 8, standard ARM | standard assembler output must run |
| BL | acts as B | writes r14 | subroutines |
| r15 as source | undefined | reads PC + 8 | literal pools, ADR |
| r15 as destination | undefined | branch to the result | subroutine return |
| Load/store direction bit | ignored, offset treated as signed | decoded, standard ARM | standard assembler output must run |
| Flags N and V | read bit 31 of a 16-bit result after narrowing | bit 15 | defect from narrowing |
| Flag C | computed from signed operands, wrong for some sums and inverted on subtraction | ARM definition | defect in the lab core |
| Five audited defects of 2026-08-10 | fixed in the lab | carried across with their regressions | |
| Peripherals | none | VGA output, switches, UART, counters | demo and debug |

## 6. The chip and its environment

The design is one tile on the shared TTSKY26c die. The die is in a QFN package on the TinyTapeout breakout
board. The breakout board plugs into the TinyTapeout demo board v3. The demo board carries an RP2350B
microcontroller, one seven-segment digit, eight DIP switches, three Pmod sockets and a USB-C connector.

The RP2350B does five things for the chip.

1. It selects the design through the on-die multiplexer and drives the `ena` pin.
2. It generates the project clock. 25 MHz is requested. Any value up to 66 MHz can be set.
3. It drives the reset pin.
4. It drives or releases the eight input pins. When released, the DIP switches drive them.
5. It runs MicroPython from USB. A start-up script can do steps 1 to 4 with no computer attached.

The QSPI Pmod plugs into the bidirectional Pmod socket. The RP2350B must hold its own copies of those eight
pins as inputs. The MicroPython configuration file has a per-project setting for that.

The TinyVGA Pmod plugs into the output Pmod socket. It is a resistor ladder that turns two bits per colour
into VGA levels, plus the two sync lines. The demo board's own seven-segment digit sits on the same eight
pins through solder jumpers JP2 to JP9 and 510 ohm resistors. Those jumpers must be cut, or the digit loads
the ladder and flickers with the video. The digit is not used by this design.

The UART goes through the RP2350B, which bridges it to the USB serial port. The TinyTapeout convention puts
the chip's receive line on input pin 3 and its transmit line on output pin 4, so the demo board's serial
bridge works with no configuration. Output pin 4 belongs to the video in normal operation; the UART_EN
switch turns the video off and gives the pin to the transmit line.

The chip's core runs from the 1.8 V rail. The pins are 3.3 V. The Pmod is powered from the 3.3 V rail on the
socket.

## 7. Pin assignment

### 7.1 Inputs (`ui_in`)

| Pin | Name | Function |
|---|---|---|
| ui_in[0] | FWD_EN | 1: forwarding on. 0: stall on every dependency. Latched while reset is active. |
| ui_in[1] | DISP_SEL | 0: program view. 1: hardware view. |
| ui_in[2] | UART_EN | 1: video off, uo_out[4] is UART transmit. 0: video on. |
| ui_in[3] | UART_RX | serial receive, idle high. TinyTapeout convention. |
| ui_in[4] | QSPI_DLY0 | receive sampling delay, bit 0. Latched while reset is active. |
| ui_in[5] | QSPI_DLY1 | receive sampling delay, bit 1. Latched while reset is active. |
| ui_in[6] | BOOT_ROM | 1: fetch from the internal ROM. 0: fetch from the flash. Latched while reset is active. |
| ui_in[7] | USER | free for the program; readable through SW. In hardware view, 1 shows the meter. |

All eight pins are readable by the program through the SW register at any time.

### 7.2 Outputs (`uo_out`)

| Pin | UART_EN = 0, video | UART_EN = 1, serial debug |
|---|---|---|
| uo_out[0] | R1, red high bit | 0 |
| uo_out[1] | G1, green high bit | 0 |
| uo_out[2] | B1, blue high bit | 0 |
| uo_out[3] | VSYNC, active low | 1 |
| uo_out[4] | R0, red low bit | UART_TX, idle high |
| uo_out[5] | G0, green low bit | 0 |
| uo_out[6] | B0, blue low bit | 0 |
| uo_out[7] | HSYNC, active low | 1 |

The video pin order is the TinyTapeout TinyVGA convention. With UART_EN high the sync lines rest high and
the colour lines rest low, so the monitor shows no signal and the pins do not toggle.

### 7.3 Bidirectional pins (`uio`), all to the QSPI Pmod

| Pin | Name | Direction | Function |
|---|---|---|---|
| uio[0] | CS_FLASH | output | flash chip select, active low |
| uio[1] | SD0 | bidirectional | data bit 0 |
| uio[2] | SD1 | bidirectional | data bit 1 |
| uio[3] | SCK | output | memory clock |
| uio[4] | SD2 | bidirectional | data bit 2 |
| uio[5] | SD3 | bidirectional | data bit 3 |
| uio[6] | CS_RAM_A | output | PSRAM A chip select, active low |
| uio[7] | CS_RAM_B | output | PSRAM B chip select, held high |

The four data pins change direction during every transaction. Their enables are driven per pin.

### 7.4 Control pins

| Pin | Function |
|---|---|
| clk | project clock from the demo board, 25 MHz nominal |
| rst_n | active-low reset; asserted asynchronously, released through a two-flop synchronizer |
| ena | not used; the multiplexer isolates the design when it is not selected |

## 8. Address map

Addresses are 16-bit byte addresses. Memory words are 16 bits at even addresses. Address bit 0 is ignored
by loads and stores. Instructions are 32 bits at addresses that are multiples of 4, little-endian.

| Range | Device | Access | Mapping |
|---|---|---|---|
| 0x0000 to 0x7FFF | flash | fetch, LDR | flash byte address = address |
| 0x0000 to 0x003F | internal ROM | fetch only, when BOOT_ROM = 1 | shadows the flash |
| 0x8000 to 0xFEFF | PSRAM A | LDR, STR | PSRAM byte address = address - 0x8000 |
| 0xFF00 to 0xFFFF | peripherals | LDR, STR | section 3.4 |

A store to the flash range does nothing. A fetch from the PSRAM or peripheral range is not supported.

## 9. Operating modes

| Scenario | Switches | What happens |
|---|---|---|
| Standalone demo | DISP_SEL 0, UART_EN 0, BOOT_ROM 0 | the program in the flash runs and draws on the screen |
| Proof of life, no memory Pmod | BOOT_ROM 1, DISP_SEL 0 | the ROM program counts on the screen |
| Is it fetching? | DISP_SEL 1 | the screen shows the program counter; the background turns blue while the bus works |
| Serial debug | UART_EN 1 | the program prints and reads over USB serial; the screen is blank |
| Pipeline study | BOOT_ROM 1, FWD_EN 0 or 1 | the ROM program's count rate changes about 2x; the meter shows it. On flash programs FWD_EN has no visible effect |

## 10. Reset and boot

1. The demo board holds `rst_n` low. The chip latches QSPI_DLY and BOOT_ROM from the input pins.
2. The program counter becomes 0x0000. The flags become 0. The general registers are unchanged, so the
   program must write a register before it reads it. The peripheral registers take their reset values.
3. The demo board releases `rst_n`. The controller starts the first fetch at flash address 0, or ROM
   address 0 when BOOT_ROM is set.
4. No chip mode command is sent. The flash must already have its quad-enable bit set; that bit is
   non-volatile and is set once during bring-up.

## 11. Area budget and priority

Measured figures: the probe with the streaming controller is 3,517 cells, 642 flip-flops, 67.0%
utilization, 57 gate levels; the VGA timing generator and four-digit renderer are 306 cells and 59
flip-flops, 5.2%. The projected total with the peripherals and the UART is about 76% before the controller
rewrite and about 71% after it. The cap for this design is 72% at the synthesis estimate, so the cap holds
only if the rewrite's savings appear in the real synthesis. Features are added in the order below and the
design is re-synthesized after each one. A feature that breaks the cap is dropped, starting from the bottom.

1. Must: the controller rewrite. It removes the duplicate instruction and shift registers found in the
   probe, worth about 5% of the tile, and it fixes the four probe defects.
2. Must: the VGA timing generator and four-digit renderer, the peripheral decode, SW, the hardware view.
3. Must: the internal demo ROM, isolated from the controller.
4. Should: the UART, trimmed to transmit-only before it is cut.
5. Nice: the retired-per-frame meter.

## 12. Clock and timing

- Core clock 25 MHz, and it is the VGA pixel clock: 25.000 MHz gives 59.5 frames per second, which
  monitors accept. The clock cannot be lowered to ease timing; the design must close at 25 MHz. Memory
  clock 12.5 MHz from a toggle flip-flop.
- The sky130 output pad is rated 33 MHz. The TinyTapeout multiplexer adds a measured 20 ns round trip.
  With the flash's 6 ns clock-to-output and 3 ns of setup, one memory clock period of 80 ns leaves 51 ns
  of margin.
- Timing constraints follow TinyQV: 65% of the period is budgeted to input and output delay on the Pmod
  pins, 20% on the memory clock pin, and 2.5 ns of extra clock uncertainty for the multiplexer.
- The register file and status register write on the falling edge. Those paths get half a period.
- The board clock stays at 25 MHz because of the video timing, even if hardening closes higher.

## 13. Expected performance

| Case | Core cycles per instruction |
|---|---|
| Straight-line code | 16 |
| Taken branch | about 56 |
| LDR or STR to PSRAM | about 88 to 96 |
| LDR from flash (literal pool) | about 104 |
| Peripheral LDR or STR | as straight-line code |
| ROM program, forwarding on | 1 |
| ROM program, forwarding off | 1.6 to 1.8 |

Cycle model on three workload mixes (fractions of taken branches, loads or stores, adjacent dependencies):
16.0 straight-line (0, 0, 0.3), 33.5 loop-heavy (0.2, 0.1, 0.4), 47.5 load-heavy (0.1, 0.3, 0.4) core cycles
per instruction under the drain policy. The silicon measurement calibrates the model
(`scratch_pad/2026-09-06_sep/01_architecture_exploration/scripts/cycle_model.py`).

At 25 MHz this is roughly 1 to 1.5 million instructions per second in loops, and enough to drive a display
or a serial console. The pipeline is idle most of the time. That is a known and accepted property of a
cache-less serial-memory design, and it is what the forwarding switch and the counters let you measure.

## 14. What "works" means

The chip is done when every item below passes.

1. A golden model exists: a Python simulator of the instruction subset, written from the ARM architecture
   definition and not from the RTL, with the address map and the peripherals.
2. An assembler exists: `arm-none-eabi-as` for real programs, and a Python encoder for the subset that is
   checked byte for byte against it.
3. Behavioural models exist for the W25Q128JV flash (EBh, mode byte, address auto-increment, quad-enable
   state) and the APS6404L PSRAM (EBh, 38h, chip-select-low time limit, chip-select-high gap), written
   from the datasheets.
4. cocotb tests pass at RTL: one directed test per instruction class with flag checks; the five lab
   regressions re-encoded; random programs compared against the golden model at the end of execution;
   UART loopback; the ROM boot; the hardware view; a VGA sync-timing check; a frame-capture test that renders one frame to
   an image and compares it; the demo program drawing on the screen end to end; the memory model counting
   exactly one bus transaction per load or store against the golden model; the mux round trip swept 0 to
   40 ns across the three strap settings with at least two settings passing to 30 ns; one deliberately
   failing negative test so the suite is known to see.
5. Hardening closes at 25 MHz with zero setup, hold, DRC, LVS and antenna failures across the nine corners,
   per the `ttsky26c-hardening-guardrails` note, and the metrics are snapshotted.
6. The same cocotb tests pass on the powered gate-level netlist.
7. The TinyTapeout CI test, docs and GDS workflows are green on the pushed repository.

## 15. Programming tools

- Assemble with `arm-none-eabi-as -march=armv4`, link at address 0, and `objcopy -O binary` to make the
  flash image. Install `binutils-arm-none-eabi`. Constants must fit 16 bits. Do not use instructions
  outside section 3.1.
- Write the image into the Pmod flash with the TinyTapeout flasher web tool. The flasher parks the chip off
  the bus, writes over single-lane SPI, and verifies.
- Set the flash quad-enable bit once with a short MicroPython script (write enable 06h, then 31h with bit
  S9 = 1). Verify with the JEDEC ID, which reads EF 70 18. Drive `uio[4]` and `uio[5]` high during those
  single-lane commands, because until the bit is set those pins are write-protect and hold.

## 16. Bring-up procedure, when the boards arrive

1. Cut the digit jumpers JP2 to JP9 on the demo board. Fit the breakout board and the TinyVGA Pmod on the
   output socket. Connect a monitor. Do not fit the memory Pmod yet.
2. Set BOOT_ROM 1, DISP_SEL 0, UART_EN 0. Select the design, set 25 MHz, release reset. The screen shows
   four digits counting.
3. Set DISP_SEL 1. The screen shows the program counter cycling on a black background.
4. Fit the memory Pmod. Set the quad-enable bit. Program a test image. Set BOOT_ROM 0. Reset. The screen
   shows the test program's output, and in hardware view the background turns blue while the bus works.
5. Set UART_EN 1. The screen goes blank. Open the serial console. Run the console test program.
6. Try QSPI_DLY values 1, 2 and 3 and note which work. The clock stays at 25 MHz.
7. Film the standalone demo with a USB power brick, the monitor, and no computer.

## 17. Decisions taken in this specification

These were decided while writing this document. Each one changes the RTL that will be written. Say so if
any is wrong.

1. Standard ARM encoding for the subset: branch offsets in words from PC + 8, the load/store direction bit
   decoded, BL writes r14, r15 readable as PC + 8 and writable as a branch. The lab's five regressions must
   be re-encoded for branches and negative offsets.
2. The flag logic is rewritten to the ARM definition and checked against the golden model. The lab ALU is
   not the reference.
3. The general registers are not reset.
4. The UART uses the TinyTapeout pins and a mode switch turns the video off while it is on.
5. The controller uses no volatile chip mode and boots from a cold Pmod.
6. The internal ROM and the two counters are conditional on the 72% cap.
7. The TinyVGA Pmod replaces the seven-segment digit (2026-09-05). A hardware renderer draws VGA_VAL as
   four large digits; the core clock is fixed at 25 MHz as the pixel clock; the board's digit jumpers are
   cut. Measured at 5.2% of the tile.
8. Architecture exploration (2026-09-06): the stall policy is drain with a valid/ready fetch and 0b1111
   bubbles; forwarding is kept and is live only in ROM mode, FWD_EN latched at reset; the internal ROM
   outranks the UART and is isolated from the controller; the controller tick ratio is a parameter; the
   counters become one retired-per-frame meter. Continuous read, a 1:1 memory clock, a branch-target
   cache, a ROM macro, a latch buffer and a parallel data path are parked for the follow-on chip.

## 18. Open questions for the user

1. Install `binutils-arm-none-eabi` on this machine, or rely on the Python encoder alone for the sprint.
2. Confirm the repository name `ttsky26c-arm16` and create the GitHub repository when ready to push.
3. Order one QSPI Pmod and one TinyVGA Pmod from the TinyTapeout store.
