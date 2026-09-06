// Renderer A: an 8x8 bitmap of fat pixels (64 x 60 screen pixels each), two 6-bit colours.
// Program writes rows 0..7 (8 bits each) and the two colour registers.
module vga_bitmap8(
    input clk, input rst,
    input wr, input [3:0] addr, input [15:0] wdata,     // addr 0..7 rows, 8 fg colour, 9 bg colour
    output [7:0] uo_out
);
    wire [9:0] h, v; wire act, hs, vs;
    vga_timing t(.clk(clk), .rst(rst), .hcount(h), .vcount(v), .active(act), .hsync_n(hs), .vsync_n(vs));
    reg [7:0] row [0:7]; reg [5:0] fg, bg;
    integer i;
    always @(posedge clk) begin
        if (rst) begin for (i=0;i<8;i=i+1) row[i] <= 0; fg <= 6'b111111; bg <= 0; end
        else if (wr) begin
            if (addr < 8) row[addr[2:0]] <= wdata[7:0];
            else if (addr == 8) fg <= wdata[5:0];
            else if (addr == 9) bg <= wdata[5:0];
        end
    end
    // vertical: 8 rows of 60 lines; a line counter avoids a divider
    reg [5:0] lcnt; reg [2:0] ry;
    always @(posedge clk) begin
        if (rst | (h == 10'd799 && v == 10'd524)) begin lcnt <= 0; ry <= 0; end
        else if (h == 10'd799) begin
            if (lcnt == 6'd59) begin lcnt <= 0; ry <= ry + 3'd1; end else lcnt <= lcnt + 6'd1;
        end
    end
    wire inx = (h >= 10'd64) & (h < 10'd576);
    wire [2:0] rx = h[8:6] - 3'd1;         // (h-64)>>6 for 64 <= h < 576
    wire lit = act & inx & (v < 10'd480) & row[ry][7-rx];
    wire [5:0] col = act ? (lit ? fg : bg) : 6'b0;
    // TinyVGA: uo = {HSYNC, B0, G0, R0, VSYNC, B1, G1, R1}
    reg [7:0] o;
    always @(posedge clk) o <= {hs, col[0], col[2], col[4], vs, col[1], col[3], col[5]};
    assign uo_out = o;
endmodule
