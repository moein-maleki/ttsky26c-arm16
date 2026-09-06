// Reset synchronizer: rst_n asserts asynchronously, releases through two flops (spec 7.4).
`default_nettype none
module reset_synchronizer (
    input  wire clk,
    input  wire rst_n,
    output wire rst_out
);
    reg sync_first;
    reg sync_second;

    assign rst_out = sync_second;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_first  <= 1'b1;
            sync_second <= 1'b1;
        end else begin
            sync_first  <= 1'b0;
            sync_second <= sync_first;
        end
    end
endmodule
`default_nettype wire
