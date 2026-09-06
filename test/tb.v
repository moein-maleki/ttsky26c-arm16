`default_nettype none
`timescale 1ns / 1ps

/* Testbench: instantiates the arm16 top and exposes convenience nets for the cocotb suite (test.py).
   The QSPI nets follow the Pmod pin map of docs/spec.md 7.3. */
module tb ();

  initial begin
    $dumpfile("tb.fst");
    $dumpvars(0, tb);
    #1;
  end

  reg clk;
  reg rst_n;
  reg ena;
  reg [7:0] ui_in;
  reg [7:0] uio_in;
  wire [7:0] uo_out;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;

  // QSPI convenience nets (spec 7.3)
  wire       qspi_sck   = uio_out[3];
  wire       cs_flash_n = uio_out[0];
  wire       cs_ram_n   = uio_out[6];
  wire [3:0] sd_out     = {uio_out[5], uio_out[4], uio_out[2], uio_out[1]};
  wire [3:0] sd_oe      = {uio_oe[5], uio_oe[4], uio_oe[2], uio_oe[1]};

`ifdef GL_TEST
  wire VPWR = 1'b1;
  wire VGND = 1'b0;
`endif

  tt_um_moein_maleki_arm16 user_project (
`ifdef GL_TEST
      .VPWR(VPWR),
      .VGND(VGND),
`endif
      .ui_in  (ui_in),
      .uo_out (uo_out),
      .uio_in (uio_in),
      .uio_out(uio_out),
      .uio_oe (uio_oe),
      .ena    (ena),
      .clk    (clk),
      .rst_n  (rst_n)
  );

endmodule
