`default_nettype none
`timescale 1ns / 1ps

// Testbench observer. All observations come from package pins. The first HSYNC falling edge
// establishes x=656 on line zero after reset. Every later sync level is checked against that anchor.
module video_monitor (
    input wire clk,
    input wire rst_n,
    input wire enable,
    input wire quiet_bus,
    input wire [7:0] video,
    input wire [7:0] bus_out,
    input wire [7:0] bus_oe,
    output reg [31:0] errors,
    output reg [31:0] sample_count,
    output reg [31:0] frame_number,
    output reg [31:0] capture_sequence,
    output reg [31:0] capture_frame,
    output reg [167:0] captured_pixels,
    output reg [31:0] first_error_sample
);
    reg anchored;
    reg previous_hsync;
    integer x;
    integer y;
    integer digit;
    integer segment;
    integer relative_x;
    reg [167:0] pixels;
    reg [27:0] seen;
    reg [5:0] colour;
    reg [31:0] error_now;

    // Sample after the falling edge, outside the DUT's rising-edge update and cell-delay window.
    always @(negedge clk) begin
        #5;
        if (!rst_n || !enable) begin
            anchored = 1'b0;
            previous_hsync = 1'b1;
            x = 0;
            y = 0;
            errors = 0;
            sample_count = 0;
            frame_number = 0;
            capture_sequence = 0;
            capture_frame = 0;
            captured_pixels = 0;
            pixels = 0;
            seen = 0;
            first_error_sample = 0;
        end else begin
            sample_count = sample_count + 1;
            error_now = 0;
            if (quiet_bus && ((bus_out !== 8'hC1) || (bus_oe !== 8'hC9)))
                error_now = error_now | 32'd8;
            if ((^video) === 1'bx)
                error_now = error_now | 32'd4;
            if (!anchored) begin
                if ((previous_hsync === 1'b1) && (video[7] === 1'b0)) begin
                    anchored = 1'b1;
                    x = 656;
                    y = 0;
                end
            end else begin
                if (x == 799) begin
                    x = 0;
                    if (y == 524) begin
                        y = 0;
                        frame_number = frame_number + 1;
                    end else begin
                        y = y + 1;
                    end
                end else begin
                    x = x + 1;
                end
            end
            if (anchored) begin
                if (video[7] !== !((x >= 656) && (x < 752)))
                    error_now = error_now | 32'd1;
                if (video[3] !== !((y >= 490) && (y < 492)))
                    error_now = error_now | 32'd2;
                if ((x == 0) && (y == 160)) begin
                    pixels = 0;
                    seen = 0;
                end
                colour = {video[0], video[4], video[1], video[5], video[2], video[6]};
                if ((x >= 64) && (x < 576)) begin
                    relative_x = (x - 64) % 128;
                    digit = (x - 64) / 128;
                    segment = -1;
                    if ((y == 176) && (relative_x == 48)) segment = 0;
                    if ((y == 208) && (relative_x == 80)) segment = 1;
                    if ((y == 272) && (relative_x == 80)) segment = 2;
                    if ((y == 304) && (relative_x == 48)) segment = 3;
                    if ((y == 272) && (relative_x == 16)) segment = 4;
                    if ((y == 208) && (relative_x == 16)) segment = 5;
                    if ((y == 240) && (relative_x == 48)) segment = 6;
                    if (segment >= 0) begin
                        pixels[(digit * 7 + segment) * 6 +: 6] = colour;
                        seen[digit * 7 + segment] = 1'b1;
                    end
                end
                if ((x == 575) && (y == 304)) begin
                    if (seen !== 28'hFFFFFFF) error_now = error_now | 32'd16;
                    captured_pixels = pixels;
                    capture_frame = frame_number;
                    capture_sequence = capture_sequence + 1;
                end
            end
            if ((errors == 0) && (error_now != 0)) first_error_sample = sample_count;
            errors = errors | error_now;
            previous_hsync = video[7];
        end
    end
endmodule
`default_nettype wire
