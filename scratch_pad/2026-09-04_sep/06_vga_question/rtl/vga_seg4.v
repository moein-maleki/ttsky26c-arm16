// Renderer B: a 16-bit value shown as four large seven-segment style hex digits, two 6-bit colours.
module vga_seg4(
    input clk, input rst,
    input wr, input [1:0] addr, input [15:0] wdata,     // 0 value, 1 fg colour, 2 bg colour
    output [7:0] uo_out
);
    wire [9:0] h, v; wire act, hs, vs;
    vga_timing t(.clk(clk), .rst(rst), .hcount(h), .vcount(v), .active(act), .hsync_n(hs), .vsync_n(vs));
    reg [15:0] val; reg [5:0] fg, bg;
    always @(posedge clk) begin
        if (rst) begin val <= 0; fg <= 6'b111111; bg <= 0; end
        else if (wr) begin
            if (addr == 0) val <= wdata; else if (addr == 1) fg <= wdata[5:0]; else if (addr == 2) bg <= wdata[5:0];
        end
    end
    // digits in x 64..576 (4 cells of 128), 3 columns of 32 px + 32 px gap; rows in y 160..320 (5 rows of 32)
    wire inx = (h >= 10'd64) & (h < 10'd576);
    wire iny = (v >= 10'd160) & (v < 10'd320);
    wire [9:0] hr = h - 10'd64; wire [9:0] vr = v - 10'd160;
    wire [1:0] dig = hr[8:7]; wire [1:0] gx = hr[6:5]; wire [2:0] gy = vr[7:5];
    wire [3:0] nib = (dig == 0) ? val[15:12] : (dig == 1) ? val[11:8] : (dig == 2) ? val[7:4] : val[3:0];
    reg [6:0] seg; // {G,F,E,D,C,B,A}
    always @(*) case (nib)
        4'h0: seg=7'h3F; 4'h1: seg=7'h06; 4'h2: seg=7'h5B; 4'h3: seg=7'h4F; 4'h4: seg=7'h66; 4'h5: seg=7'h6D;
        4'h6: seg=7'h7D; 4'h7: seg=7'h07; 4'h8: seg=7'h7F; 4'h9: seg=7'h6F; 4'hA: seg=7'h77; 4'hB: seg=7'h7C;
        4'hC: seg=7'h39; 4'hD: seg=7'h5E; 4'hE: seg=7'h79; default: seg=7'h71; endcase
    reg on;
    always @(*) begin
        on = 1'b0;
        case (gy)
            3'd0: on = (gx == 2'd1) & seg[0];                       // A
            3'd1: on = ((gx == 2'd0) & seg[5]) | ((gx == 2'd2) & seg[1]); // F, B
            3'd2: on = (gx == 2'd1) & seg[6];                       // G
            3'd3: on = ((gx == 2'd0) & seg[4]) | ((gx == 2'd2) & seg[2]); // E, C
            3'd4: on = (gx == 2'd1) & seg[3];                       // D
            default: on = 1'b0;
        endcase
    end
    wire lit = act & inx & iny & on;
    wire [5:0] col = act ? (lit ? fg : bg) : 6'b0;
    reg [7:0] o;
    always @(posedge clk) o <= {hs, col[0], col[2], col[4], vs, col[1], col[3], col[5]};
    assign uo_out = o;
endmodule
