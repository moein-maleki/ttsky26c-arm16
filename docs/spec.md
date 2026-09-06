# arm16 design specification

> Version 0.1, 2026-09-04. Status: for review, before any RTL is written.
> Target: TinyTapeout shuttle TTSKY26c, sky130A, one 2x2 tile, deadline 2026-09-07 20:00 UTC.
> Author: Moein Maleki. Written in Simplified Technical English.

## 1. Purpose

arm16 is a small ARM processor. It fetches its program from an external flash chip and keeps its data in an
external RAM chip. It shows what it does on the demo board's seven-segment digit. It talks to a computer
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
| Peripherals | seven-segment display, switch input, UART, two counters |
| Core clock | 25 MHz nominal, set by the demo board |
| Memory clock | 12.5 MHz, half the core clock |
| Expected speed | about one instruction per 16 to 24 core cycles in straight-line code |
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
on every read-after-write dependency when forwarding is off. A switch selects forwarding on or off at run
time, so the two behaviours can be compared on silicon. A taken branch is resolved in execute and removes
the two younger instructions. There is no branch prediction and no delay slot. The register file and the
status register write on the falling clock edge, as in the lab design.

### 3.3 Memory system

One QSPI controller serves instruction fetch and data access over the shared Pmod bus.

- Instruction fetch streams. The controller holds the flash chip select low and keeps the clock running
  while the program counter advances in sequence. A sequential 32-bit instruction costs 8 memory clocks.
  A taken branch aborts the stream and restarts it at the target, which costs 20 memory clocks of setup.
- The controller always has the next sequential instruction in flight. There is no larger buffer.
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
| 0xFF00 | DISP | read, write | bits [7:0] drive the display segments directly; 1 lights a segment |
| 0xFF02 | SW | read | bits [7:0] are the eight input pins |
| 0xFF04 | UART_DATA | read, write | write sends one byte; read returns the received byte and clears RX_VALID |
| 0xFF06 | UART_STAT | read | bit 0 TX_BUSY, bit 1 RX_VALID, bit 2 RX_OVERRUN |
| 0xFF08 | UART_DIV | read, write | core clocks per bit; reset value 217 gives 115,200 baud at 25 MHz |
| 0xFF0A | CYCLES | read | free-running 16-bit core cycle counter (optional feature, see section 11) |
| 0xFF0C | RETIRED | read | 16-bit count of instructions retired (optional feature) |
| 0xFF10 | HEXDISP | write | bits [3:0] are shown on the display as a hexadecimal digit |

A write to DISP or HEXDISP selects that source for the display. Reads of unmapped addresses return 0.
Writes to unmapped addresses do nothing.

The UART is 8 data bits, no parity, one stop bit. It has one transmit holding byte and one receive holding
byte. RX_OVERRUN is set when a byte arrives while RX_VALID is set; it clears when UART_DATA is read.

### 3.5 Internal demo ROM

When the BOOT_ROM pin is high at reset, the processor fetches addresses 0x0000 to 0x003F from a 16-instruction
ROM inside the chip instead of the flash. The ROM holds a program that counts on the display through HEXDISP
and uses no external memory. It is the proof of life if the Pmod path fails on silicon. This feature is
included only if it fits the area budget (section 11).

### 3.6 Display views

A switch selects what the digit shows.

- Program view: the last value written to DISP or HEXDISP.
- Hardware view: the hexadecimal digit of program counter bits [5:2], and the decimal point lit while the
  QSPI bus is active. This view works even when the program is wrong.

## 4. Features excluded

| Feature | Why it is out |
|---|---|
| Cache | 9,664 flip-flops in the lab design; the tile holds about 1,500 in total |
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
| Branch prediction, a second memory port, DTR reads | future work, none proven on TinyTapeout |

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
| Peripherals | none | display, switches, UART, counters | demo and debug |

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

The seven-segment digit is connected to the eight output pins through solder jumpers and 510 ohm resistors.
The digit is common cathode: an output pin at logic 1 lights its segment.

The UART goes through the RP2350B, which bridges it to the USB serial port. The TinyTapeout convention puts
the chip's receive line on input pin 3 and its transmit line on output pin 4, so the demo board's serial
bridge works with no configuration.

The chip's core runs from the 1.8 V rail. The pins are 3.3 V. The Pmod is powered from the 3.3 V rail on the
socket.

## 7. Pin assignment

### 7.1 Inputs (`ui_in`)

| Pin | Name | Function |
|---|---|---|
| ui_in[0] | FWD_EN | 1: forwarding on. 0: stall on every dependency. Read at any time. |
| ui_in[1] | DISP_SEL | 0: program view. 1: hardware view. |
| ui_in[2] | UART_EN | 1: uo_out[4] is UART transmit. 0: uo_out[4] is segment E. |
| ui_in[3] | UART_RX | serial receive, idle high. TinyTapeout convention. |
| ui_in[4] | QSPI_DLY0 | receive sampling delay, bit 0. Latched while reset is active. |
| ui_in[5] | QSPI_DLY1 | receive sampling delay, bit 1. Latched while reset is active. |
| ui_in[6] | BOOT_ROM | 1: fetch from the internal ROM. 0: fetch from the flash. Latched while reset is active. |
| ui_in[7] | USER | free for the program; readable through SW. |

All eight pins are readable by the program through the SW register at any time.

### 7.2 Outputs (`uo_out`)

| Pin | Program view | Hardware view | UART_EN = 1 |
|---|---|---|---|
| uo_out[0] | segment A | segment A of the PC digit | same |
| uo_out[1] | segment B | segment B | same |
| uo_out[2] | segment C | segment C | same |
| uo_out[3] | segment D | segment D | same |
| uo_out[4] | segment E | segment E | UART_TX, idle high |
| uo_out[5] | segment F | segment F | same |
| uo_out[6] | segment G | segment G | same |
| uo_out[7] | decimal point | QSPI bus active | same |

Segment order A to G, decimal point last, matches the demo board wiring.

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
| Standalone demo | DISP_SEL 0, UART_EN 0, BOOT_ROM 0 | the program in the flash runs and drives the digit |
| Proof of life, no Pmod | BOOT_ROM 1, DISP_SEL 0 | the ROM program counts on the digit |
| Is it fetching? | DISP_SEL 1 | the digit shows PC bits [5:2]; the point lights while the bus works |
| Serial debug | UART_EN 1 | the program prints and reads over USB serial; segment E is lost |
| Pipeline study | FWD_EN 0 or 1 | compare CYCLES and RETIRED over the same program |

## 10. Reset and boot

1. The demo board holds `rst_n` low. The chip latches QSPI_DLY and BOOT_ROM from the input pins.
2. The program counter becomes 0x0000. The flags become 0. The general registers are unchanged, so the
   program must write a register before it reads it. The peripheral registers take their reset values.
3. The demo board releases `rst_n`. The controller starts the first fetch at flash address 0, or ROM
   address 0 when BOOT_ROM is set.
4. No chip mode command is sent. The flash must already have its quad-enable bit set; that bit is
   non-volatile and is set once during bring-up.

## 11. Area budget and priority

Measured figures for the probe with the streaming controller: 3,517 cells, 642 flip-flops, 67.0%
utilization, 57 gate levels. The cap for this design is 72% at the synthesis estimate. Features are added
in the order below and the design is re-synthesized after each one. A feature that breaks the cap is
dropped, starting from the bottom of the list.

1. Must: the controller rewrite. It removes the duplicate instruction and shift registers found in the
   probe, worth about 5% of the tile, and it fixes the four probe defects.
2. Must: peripheral decode, DISP, SW, HEXDISP, the hardware view.
3. Must: UART.
4. Should: the internal demo ROM.
5. Nice: CYCLES and RETIRED.

## 12. Clock and timing

- Core clock 25 MHz. Memory clock 12.5 MHz from a toggle flip-flop.
- The sky130 output pad is rated 33 MHz. The TinyTapeout multiplexer adds a measured 20 ns round trip.
  With the flash's 6 ns clock-to-output and 3 ns of setup, one memory clock period of 80 ns leaves 51 ns
  of margin.
- Timing constraints follow TinyQV: 65% of the period is budgeted to input and output delay on the Pmod
  pins, 20% on the memory clock pin, and 2.5 ns of extra clock uncertainty for the multiplexer.
- The register file and status register write on the falling edge. Those paths get half a period.
- If hardening closes 25 MHz with margin, the demo board can be set higher. 30 MHz is the next target.

## 13. Expected performance

| Case | Core cycles per instruction |
|---|---|
| Straight-line code, forwarding on | 16 to 24 |
| Taken branch | about 56 |
| LDR or STR to PSRAM | about 88 to 96 |
| LDR from flash (literal pool) | about 104 |
| Peripheral LDR or STR | as straight-line code |

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
   UART loopback; the ROM boot; the hardware view; the demo program driving the digit end to end.
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

1. Fit the breakout board. Do not fit the Pmod yet.
2. Set BOOT_ROM 1, DISP_SEL 0, UART_EN 0. Select the design, set 25 MHz, release reset. The digit counts.
3. Set DISP_SEL 1. The digit shows the program counter digit cycling and the point stays dark.
4. Fit the Pmod. Set the quad-enable bit. Program a test image. Set BOOT_ROM 0. Reset. The digit shows the
   test program's output, and the point lights in hardware view.
5. Set UART_EN 1. Open the serial console. Run the console test program.
6. Try QSPI_DLY values 1, 2 and 3 and note which work. Raise the clock in steps and note the limit.
7. Film the standalone demo with a USB power brick and no computer.

## 17. Decisions taken in this specification

These were decided while writing this document. Each one changes the RTL that will be written. Say so if
any is wrong.

1. Standard ARM encoding for the subset: branch offsets in words from PC + 8, the load/store direction bit
   decoded, BL writes r14, r15 readable as PC + 8 and writable as a branch. The lab's five regressions must
   be re-encoded for branches and negative offsets.
2. The flag logic is rewritten to the ARM definition and checked against the golden model. The lab ALU is
   not the reference.
3. The general registers are not reset.
4. The UART uses the TinyTapeout pins and a mode switch takes segment E away while it is on.
5. The controller uses no volatile chip mode and boots from a cold Pmod.
6. The internal ROM and the two counters are conditional on the 72% cap.

## 18. Open questions for the user

1. Install `binutils-arm-none-eabi` on this machine, or rely on the Python encoder alone for the sprint.
2. Confirm the repository name `ttsky26c-arm16` and create the GitHub repository when ready to push.
3. Order one QSPI Pmod from the TinyTapeout store.
