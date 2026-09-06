// 640x480 at 60 Hz from a 25 MHz pixel clock. Sync pulses active low. Registered outputs.
module vga_timing(
    input clk, input rst,
    output reg [9:0] hcount, output reg [9:0] vcount,
    output reg active, output reg hsync_n, output reg vsync_n
);
    wire h_last = (hcount == 10'd799);
    wire v_last = (vcount == 10'd524);
    always @(posedge clk) begin
        if (rst) begin hcount <= 0; vcount <= 0; end
        else begin
            hcount <= h_last ? 10'd0 : hcount + 10'd1;
            if (h_last) vcount <= v_last ? 10'd0 : vcount + 10'd1;
        end
        active  <= (hcount < 10'd640) & (vcount < 10'd480);
        hsync_n <= ~((hcount >= 10'd656) & (hcount < 10'd752));
        vsync_n <= ~((vcount >= 10'd490) & (vcount < 10'd492));
    end
endmodule
