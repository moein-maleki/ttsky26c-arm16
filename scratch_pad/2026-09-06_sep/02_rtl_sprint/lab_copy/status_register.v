module status_register(
    input               clk,
    input               rst,
    input       [3:0]   status_input,
    input               do_update_sr,

    output reg  [3:0]   status_output
);

    always @(negedge clk, posedge rst) begin
        if(rst)                 status_output <= 4'b0;
        else if(do_update_sr)   status_output <= status_input;
        else                    status_output <= status_output;
    end

endmodule