`default_nettype none
`timescale 1ns / 1ps

/* Testbench: instantiates the arm16 top and exposes convenience nets for the cocotb suite (test.py).
   The QSPI nets follow the Pmod pin map of docs/spec.md 7.3. */
module tb ();

`ifdef ARM16_WAVES
  initial begin
    $dumpfile("tb.fst");
    $dumpvars(0, tb);
    #1;
  end
`endif

  reg clk;
`ifdef ARM16_NATIVE_CLOCK
  initial clk = 1'b0;
  always #20 clk = ~clk;
`endif
  reg rst_n;
  reg ena;
  reg [7:0] ui_in;
  reg [7:0] uio_in;
  wire [7:0] uo_out;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;

  reg video_probe_enable = 1'b0;
  reg [1:0] video_probe_fault = 2'b00;
  wire [31:0] video_probe_errors;
  video_monitor_probe video_probe_unit (
      .clk(clk), .enable(video_probe_enable), .fault(video_probe_fault),
      .errors(video_probe_errors)
  );

  reg video_monitor_enable = 1'b0;
  reg video_monitor_quiet_bus = 1'b0;
  wire [31:0] video_errors;
  wire [31:0] video_sample_count;
  wire [31:0] video_frame_number;
  wire [31:0] video_capture_sequence;
  wire [31:0] video_capture_frame;
  wire [167:0] video_captured_pixels;
  wire [31:0] video_first_error_sample;

  video_monitor video_monitor_unit (
      .clk(clk), .rst_n(rst_n), .enable(video_monitor_enable),
      .quiet_bus(video_monitor_quiet_bus), .video(uo_out),
      .bus_out(uio_out), .bus_oe(uio_oe), .errors(video_errors),
      .sample_count(video_sample_count), .frame_number(video_frame_number),
      .capture_sequence(video_capture_sequence), .capture_frame(video_capture_frame),
      .captured_pixels(video_captured_pixels), .first_error_sample(video_first_error_sample)
  );

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
