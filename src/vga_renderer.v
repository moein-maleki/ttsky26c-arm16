// 640x480 at 60 Hz from the 25 MHz core clock and a four-digit seven-segment style renderer of a
// 16-bit value (spec 3.4). Digits occupy x 64..576 (four cells of 128: three 32-pixel columns and a
// 32-pixel gap) and y 160..320 (five rows of 32). Output pins in TinyVGA order
// {HSYNC, B0, G0, R0, VSYNC, B1, G1, R1}; colours blank while enable_in is low.
// Measured 306 cells and 59 flops in scratch_pad/2026-09-04_sep/06_vga_question.
`default_nettype none
module vga_renderer (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable_in,
    input  wire [15:0] value_in,
    input  wire [5:0]  fg_in,
    input  wire [5:0]  bg_in,
    output reg  [7:0]  pins_out,
    output wire        vsync_out
);
    wire       h_last;
    wire       v_last;
    wire       in_x;
    wire       in_y;
    wire [9:0] h_rel;
    wire [9:0] v_rel;
    wire [1:0] digit;
    wire [1:0] grid_x;
    wire [2:0] grid_y;
    wire       lit_next;
    wire [5:0] colour;

    reg [9:0] h_count;
    reg [9:0] v_count;
    reg       active;
    reg       hsync_n;
    reg       vsync_n;
    reg       lit;
    reg [3:0] nibble;
    reg [6:0] segments;
    reg       segment_on;

    assign h_last    = (h_count == 10'd799);
    assign v_last    = (v_count == 10'd524);
    assign in_x      = (h_count >= 10'd64) & (h_count < 10'd576);
    assign in_y      = (v_count >= 10'd160) & (v_count < 10'd320);
    assign h_rel     = h_count - 10'd64;
    assign v_rel     = v_count - 10'd160;
    assign digit     = h_rel[8:7];
    assign grid_x    = h_rel[6:5];
    assign grid_y    = v_rel[7:5];
    assign lit_next  = in_x & in_y & segment_on;
    assign colour    = (active & enable_in) ? (lit ? fg_in : bg_in) : 6'b000000;
    assign vsync_out = vsync_n;

    always @(posedge clk) begin
        if (rst) begin
            h_count <= 10'd0;
            v_count <= 10'd0;
        end else begin
            h_count <= h_last ? 10'd0 : h_count + 10'd1;
            if (h_last) begin
                v_count <= v_last ? 10'd0 : v_count + 10'd1;
            end
        end
        active   <= (h_count < 10'd640) & (v_count < 10'd480);
        hsync_n  <= ~((h_count >= 10'd656) & (h_count < 10'd752));
        vsync_n  <= ~((v_count >= 10'd490) & (v_count < 10'd492));
        lit      <= lit_next;
        pins_out <= {hsync_n, colour[0], colour[2], colour[4], vsync_n, colour[1], colour[3], colour[5]};
    end

    always @* begin
        nibble = value_in[3:0];
        case (digit)
            2'd0: nibble = value_in[15:12];
            2'd1: nibble = value_in[11:8];
            2'd2: nibble = value_in[7:4];
            default: nibble = value_in[3:0];
        endcase
    end

    always @* begin
        segments = 7'h71;
        case (nibble)
            4'h0: segments = 7'h3F;
            4'h1: segments = 7'h06;
            4'h2: segments = 7'h5B;
            4'h3: segments = 7'h4F;
            4'h4: segments = 7'h66;
            4'h5: segments = 7'h6D;
            4'h6: segments = 7'h7D;
            4'h7: segments = 7'h07;
            4'h8: segments = 7'h7F;
            4'h9: segments = 7'h6F;
            4'hA: segments = 7'h77;
            4'hB: segments = 7'h7C;
            4'hC: segments = 7'h39;
            4'hD: segments = 7'h5E;
            4'hE: segments = 7'h79;
            default: segments = 7'h71;
        endcase
    end

    always @* begin
        segment_on = 1'b0;
        case (grid_y)
            3'd0: segment_on = (grid_x == 2'd1) & segments[0];
            3'd1: segment_on = ((grid_x == 2'd0) & segments[5]) | ((grid_x == 2'd2) & segments[1]);
            3'd2: segment_on = (grid_x == 2'd1) & segments[6];
            3'd3: segment_on = ((grid_x == 2'd0) & segments[4]) | ((grid_x == 2'd2) & segments[2]);
            3'd4: segment_on = (grid_x == 2'd1) & segments[3];
            default: segment_on = 1'b0;
        endcase
    end
endmodule
`default_nettype wire
