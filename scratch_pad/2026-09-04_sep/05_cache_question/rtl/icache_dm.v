// Direct-mapped instruction cache, one 32-bit instruction per line, flop storage.
// 16-bit byte address: index = addr[IDX+1:2], tag = addr[15:IDX+2].
module icache_dm #(parameter LINES = 8, parameter IDX = 3) (
    input               clk,
    input               rst,
    input               flush,          // invalidate all
    input       [15:0]  addr,           // lookup address (PC)
    output              hit,
    output      [31:0]  rdata,
    input               fill_en,        // write a line on miss return
    input       [15:0]  fill_addr,
    input       [31:0]  fill_data
);
    localparam TAGW = 16 - IDX - 2;
    reg [31:0]     data [0:LINES-1];
    reg [TAGW-1:0] tag  [0:LINES-1];
    reg [LINES-1:0] valid;

    wire [IDX-1:0]  idx  = addr[IDX+1:2];
    wire [TAGW-1:0] atag = addr[15:IDX+2];
    wire [IDX-1:0]  fidx = fill_addr[IDX+1:2];

    assign hit   = valid[idx] & (tag[idx] == atag);
    assign rdata = data[idx];

    integer i;
    always @(posedge clk) begin
        if (rst | flush) valid <= {LINES{1'b0}};
        else if (fill_en) begin
            data[fidx]  <= fill_data;
            tag[fidx]   <= fill_addr[15:IDX+2];
            valid[fidx] <= 1'b1;
        end
    end
endmodule
