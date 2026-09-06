# 06_vga_question: TinyVGA Pmod instead of the seven-segment digit

> 2026-09-05. Question from the user: what must be added to drive the TinyVGA Pmod instead of the digit, and
> what utilization would the 2x2 need. Method: three VGA blocks written and synthesized on sky130 in isolation
> (`rtl/`, `scripts/`, `evidence/`); totals projected from the measured core.

## Measured blocks (sky130_fd_sc_hd, flattened, placed estimate x1.487, tile 72,565 um^2)

| Block | What it is | Cells | Flops | Placed um^2 | Tile |
|---|---|---|---|---|---|
| vga_timing | 640x480 at 60 Hz counters, sync, active flag, from a 25 MHz clock | 90 | 23 | 1,280 | 1.8% |
| vga_seg4 | timing plus a 16-bit register drawn as four large seven-segment hex digits, two colours | 306 | 59 | 3,751 | 5.2% |
| vga_bitmap8 | timing plus an 8x8 bitmap of fat pixels written by the program, two colours | 424 | 116 | 7,143 | 9.8% |

## Projected 2x2 totals

| Configuration | Utilization |
|---|---|
| Core with streaming controller (measured) | 67.0% |
| plus peripherals, SW, UART (about 4%) and vga_seg4 | about 76% |
| plus peripherals, SW, UART and vga_bitmap8 | about 81% |
| either, after the controller rewrite removes the duplicate registers (about 5%) | about 71% or 76% |

The seven-segment path it replaces is under 1%. The 72% cap holds only with the four-digit renderer and only
if the controller savings materialize; the bitmap renderer needs the UART dropped or the cap raised.

## What changes beyond area

- All eight `uo_out` pins become R1, G1, B1, VSYNC, R0, G0, B0, HSYNC. The UART transmit line loses its
  pin. Keep the UART only through the mode switch: UART_EN high turns the video off and puts TX on
  `uo_out[4]`, exactly as it took segment E before.
- The core clock is locked to 25 MHz because it is the pixel clock. There is no 20 MHz fallback if timing
  is tight. 25.000 MHz gives 59.5 Hz, which monitors accept.
- The demo board's digit hangs on the same eight pins through solder jumpers JP2 to JP9 and 510 ohm
  resistors. Cut them, or the LED loads the Pmod's resistor ladder and the digit flickers with video.
- What the program can show is a few registers rendered by hardware: a 16-bit value as four digits, or an
  8x8 picture. A framebuffer or text needs memory the tile does not have, and streaming pixels from the
  PSRAM would take the bus away from instruction fetch during the whole active frame.
- Verification adds a sync-timing check and a frame capture test that renders one frame to an image, the
  pattern the TinyTapeout VGA projects use.

## Recommendation

If the video output is wanted, take vga_seg4 with the UART kept behind the mode switch, and measure the
whole design after the controller rewrite before committing. It is a nicer demo than one digit and the
program interface stays a single 16-bit write. If the sprint is the priority, the digit costs nothing and
carries no clock lock.
