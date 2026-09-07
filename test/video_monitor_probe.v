`timescale 1ns / 1ps
// Independent pin source used only to test the observer. Its faults do not alter DUT pins.
`default_nettype none
module video_monitor_probe (
    input wire clk,
    input wire enable,
    input wire [1:0] fault,
    output wire [31:0] errors
);
    reg [9:0] h = 0;
    reg [9:0] v = 0;
    wire hs = !((h >= 656 && h < 752) || (fault == 1 && v == 1 && h >= 600 && h < 656));
    wire vs = !((v >= 490 && v < 492) || (fault == 2 && v == 1 && h >= 600 && h < 656));
    wire [7:0] pixels = {hs, 3'b000, vs, 3'b000};
    always @(posedge clk) begin
        if (!enable) begin
            h <= 0;
            v <= 0;
        end else if (h == 799) begin
            h <= 0;
            v <= v == 524 ? 0 : v + 1;
        end else begin
            h <= h + 1;
        end
    end
    video_monitor observer_unit (
        .clk(clk), .rst_n(enable), .enable(enable), .quiet_bus(1'b0),
        .video(pixels), .bus_out(8'hC1), .bus_oe(8'hC9), .errors(errors),
        .sample_count(), .frame_number(), .capture_sequence(), .capture_frame(),
        .captured_pixels(), .first_error_sample()
    );
endmodule
`default_nettype wire
