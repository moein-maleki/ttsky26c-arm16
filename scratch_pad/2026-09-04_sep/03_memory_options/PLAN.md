# 03_memory_options: what the memory research decided, and what the design must now include

> 2026-09-04. The user chose TTSKY26c on the held 2x2 tile (deadline 2026-09-07 20:00 UTC) and asked which
> memory is faster and what others did. `REPORT.md` answers it; this file is the checklist those answers
> impose on the design. Promoted into the design repository; the UART and peripheral items were added on
> 2026-09-04 after the user asked for a serial debug link. The forward plan is now `docs/spec.md`.

## Decisions

- [x] Memory: the Tiny Tapeout QSPI Pmod (W25Q128JVSIM flash + 2x APS6404L-3SQR-SN PSRAM). The board's own
      flash is unreachable; the RP2 emulation is 3 to 8x slower and unported to the RP2350 board.
- [x] Roles: flash holds instructions, PSRAM A holds data. Never execute from PSRAM (tCEM 8 us).
- [x] Protocol: no volatile mode. EBh in SPI mode on both parts, mode byte FFh, 38h quad write on PSRAM.
      Continuous-read arming and QPI entry are a later optimization from an on-chip init state machine.
- [x] Clock: SCK = core/2 from a toggle flop at a 25 MHz core. Upgrade path noted in REPORT.md.
- [x] Fetch: streaming with chip select held; restart on taken branch or data access; SCK gated low to stall.

## Checklist for the design repo

- [ ] Pin map exactly as the Pmod: uio0 CS0 flash, uio1 SD0, uio2 SD1, uio3 SCK, uio4 SD2, uio5 SD3,
      uio6 CS1 RAM A, uio7 CS2 RAM B (drive high; unused). All 24-bit byte addresses; PC maps 1:1 to flash bytes.
- [ ] Controller from `tinyQV/cpu/qspi_flash.v` (Apache-2.0) plus the sampling delay and negedge SCK from
      `qspi_ctrl.v`; retarget to SPI-mode EBh, add the PSRAM read and write paths with a hard word counter per
      burst well under 8 us, and tCPH (two idle cycles) before reselecting the PSRAM.
- [ ] Sampling one full SCK period after the launch edge; delay strappable 1 to 3 from `ui_in` during reset.
- [ ] Data outputs held constant when not driving (crosstalk through the TT mux).
- [ ] A four-entry 16-bit prefetch ring between the controller and IF; the pipeline stalls on empty.
- [ ] TinyQV's SDC: 65% of the period to IO delay on `uio`, 20% on SCK, 2.5/2 ns clock uncertainty.
- [ ] Bring-up notes in the datasheet: set QE once (06h, 31h S9 = 1), verify JEDEC ID EF 70 18, hold uio4
      and uio5 high during single-SPI commands, `uio_oe_pico` inputs in `config.ini`, program with
      `tinytapeout-flasher`.
- [ ] UART: 8N1, transmit and receive, one holding byte each, RX_OVERRUN flag, programmable 16-bit divisor
      with reset value 217; RX on ui_in[3] through a two-flop synchronizer; TX on uo_out[4] when UART_EN
      (ui_in[2]) is high, which turns the video off. Registers UART_DATA 0xFF04, UART_STAT 0xFF06, UART_DIV 0xFF08.
      Measure it; it is a must-have after the controller and the display.
- [ ] Peripheral window 0xFF00 to 0xFFFF decoded in the memory stage without touching the Pmod bus: VGA_VAL,
      VGA_FG, VGA_BG, SW, the hardware view on DISP_SEL, CYCLES and RETIRED if under the cap.
- [ ] VGA: 640x480 at 60 Hz timing from the 25 MHz core clock and the four-digit renderer
      (`06_vga_question/rtl/`, measured 306 cells); TinyVGA pin order on uo_out; blanked when UART_EN is high.
- [ ] Measure a DIP-selected internal demo ROM (one seven-segment program); include it if utilization stays
      under about 72%.
- [ ] cocotb model of the W25Q128JV (EBh, mode byte, auto-increment, QE state) and APS6404L (EBh, 38h, tCEM
      violation assertion, tCPH), written from the datasheets in `evidence/`.
- [ ] Order one QSPI Pmod from store.tinytapeout.com.

## Rules carried forward

Measure, do not estimate. Every artifact under `scratch_pad/<date>/<xx>_<feature>/`. No push without the
user. No AI attribution anywhere.
