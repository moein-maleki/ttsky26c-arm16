# Agent report: external-memory CPUs on Tiny Tapeout, memory paths and stall reduction (2026-09-06)

## Memory-path options

| Scheme (project) | Pins per port | Bits per clock | Latency | Throughput | MCU firmware | Silicon |
|---|---|---|---|---|---|---|
| AnemoneGrafx-8 RP2040 VRAM server (tt06) | uio[3:0] address out, uio[7:4] data in | 4 out + 4 in | about 3 serial cycles, about 12 clocks, fixed, no handshake | 16 bits per 4 clocks = 25.2 MB/s at 50.4 MHz | 2 PIO SMs + DMA; RP2040 at 100.8 MHz = 2x design clock | proven |
| pio-ram-emulator (toivoh) | 4 pins: TX 2 + RX 2 | 2 + 2 | 22 clocks start to start; 12 from the last address bit | over 8 MB/s read or over 4 MB/s write random; 8 + 8 MB/s block | PIO + DMA only; RP2040 at 2x design clock | ttihp25a example; measured on hardware |
| spi-ram-emu (23LC512 emulation, Bell) | uio[0..3] | 1 + 1 | FAST READ 8 dummy clocks | SYS/10 read, 12.5 MHz | PIO + DMA + core1; RP2040 only | standard on TT04+ boards |
| QSPI Pmod flash, continuous read pre-armed (TinyQV) | 8 uio | 4 shared | 12-cycle preamble | 4 bits per clock at 32 MHz | flasher arms the mode (M7-0 = A0h) | proven tt06, ttihp25a, ttsky25a, ttgf0p2 |
| QSPI flash, self-armed (FazyRV-ExoTiny, tt06) | same Pmod | 4 shared | first read 30 clocks, later 22 | one QSPI clock per design clock (sck = ~clk) | none, the chip arms itself | tt06 silicon |
| Dual 1-bit SPI, true Harvard (DUMBRV, ttihp25b, 2x2) | uio[3:0] instruction, uio[7:4] data | 1 + 1, SPI = clk/2 | 8 command + 16 address | 2.5 MB/s per bus at 40 MHz | none | not yet returned |
| Multiplexed parallel bus (Simplified 6502, ttsky25a) | uo = 16-bit address over 2 clocks, uio = 8-bit data, ui = data-in latch | 8 + 8 | 1 CPU cycle = 2 external clocks | about 20 MB/s | a bus server | ttsky25a |

AnemoneGrafx's scheme cannot coexist with the QSPI flash on uio; moving its channel to ui/uo collides with
VGA on all eight outputs. The pio-ram-emulator channel needs only 2 out + 2 in; toivoh multiplexed hsync
onto uio[7] in his own example to free outputs.

## Separate instruction and data buses

DUMBRV: two SPI ports, read-only instruction at 0x0000_0000, read-write data at 0x0100_0000; a 6-byte prefetch
queue; the LSU can read through the instruction port for rodata; no commentary on the trade. LISA (tt06): one
shared QSPI bus with a three-requestor arbiter (debug highest, fetch and data round-robin), separate chip
selects for flash and SRAM, a 1-line 4-instruction I-cache and an 8-line 16-byte D-cache; relaxed to 20 MHz.
HACK CPU (tt08): "we cannot fetch the 16-bit long instruction and data memory values at the same time because
we only have 24 I/O pins". KianV: shared Pmod data lines, separate selects. Goldcrest and UNAL RISCV: not
Tiny Tapeout projects (misattributed).

## Cutting the restart penalty

FazyRV-ExoTiny rtl/wb_qspi_mem.sv: sck_o = ~clk_i; INIT 8 cycles sends 35h to the PSRAM; the flash mode is
latched as a side effect of the first ROM read (crm_n = crm_r | ...), adr_init keeps 0xA5 as the mode byte,
IDLE then skips INSTR. Phases: IDLE 1, INSTR ROM 8 / RAM 2, ADDR ROM 8 / RAM 6, DUMMY 4, DATA_R 8, DATA_W
8/4/2, ACK 1. First ROM read 30 cycles, later 22 (27% saving); RAM read 22, word write 18. TinyQV instead
expects the host to arm both modes; flash preamble 12; PSRAM 0Bh read 20 cycles for 32 bits, write 16.
TinyQV multi-word: lw 9-10, lw2 15-16 (17-20% saving), lw4 23-24 (36-40%), sw 6-7, sw2 11-12, sw4 19-20
(21-29%); branch not taken 1, taken 7 (48-clock restart). No write buffering anywhere; switching chip
select aborts the transaction; no design keeps two flash streams open; no TT design uses DTR reads.
Prefetch queues: Basilisc-2816 2/3/4 words ("longer prefetch queue should help ... especially with long
memory access latencies"), DUMBRV 6 bytes, LISA 1-line I-cache.

## Pipelining versus multicycle

Arctic0 (ttgf26b): "a multi-cycle CPU ... MEM_CTRL ... stalls the CPU clock while external SPI or UART work
completes". Basilisc-2816: "there is no point in calculating faster than the memory interface allows"; "The
processor starts to operate on each bit of incoming read data as it arrives." TinyQV: "instruction fetch is
only capable of reading 16-bits per cycle, so 1 cycle/instruction throughput can only be maintained with
compressed instructions"; "Code execution is only supported from the flash ... removes the need for handling
the PSRAM refresh every 8us". FazyRV: 2-bit serial datapath matched to a 4-bit feed. Not found: any TT CPU
with a branch predictor or BTB; any measured CPI with and without forwarding.

## Parallel bus to the microcontroller

Simplified 6502 (ttsky25a): uo_out carries the 16-bit address over two clocks, uio the 8-bit data with uio_oe,
ui_in a data-in latch; internal logic at clk/2; 40 MHz; all 24 pins; repo sanjaycal/ECE298A-6502-SKY. "VC 16-bit
CPU latch trick": not found.

Sources: toivoh/tt06-retro-console (+ rp2040 firmware), toivoh/pio-ram-emulator, ttihp25a example
tt_um_toivoh_pio_ram_emu_example, toivoh/tt07-basilisc-2816-cpu, yliu-hashed/ttihp25b-dumbrv,
MichaelBell/tinyQV, MichaelBell/spi-ram-emu, meiniKi/FazyRV-ExoTiny and tt06-FazyRV-ExoTiny,
kdp1965/tt06-um-lisa, Arctic0 tt_um_Arctic0, HACK CPU tt_um_hack_cpu, Simplified 6502 tt_um_6502, KianV
ttihp0p2, tinytapeout.com/specs/memory, mole99/qspi-pmod.
