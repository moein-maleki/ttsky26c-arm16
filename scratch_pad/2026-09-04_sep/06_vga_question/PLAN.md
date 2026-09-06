# 06_vga_question: TinyVGA instead of the digit

> 2026-09-05. Question from the user: what must be added to drive the TinyVGA Pmod instead of the
> seven-segment digit, and what utilization would it need.

- [x] Write and synthesize a 640x480 timing generator, an 8x8 fat-pixel bitmap renderer and a four-digit
      seven-segment style renderer on sky130 (`rtl/`, `scripts/`, `evidence/`).
- [x] Report the pin, clock and jumper consequences and the projected utilization (`REPORT.md`).
- [x] User chose the four-digit renderer with the UART behind the mode switch; spec v0.2 (2026-09-05).
