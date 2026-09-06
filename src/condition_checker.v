// ARM condition field against the flags {N, Z, C, V}; condition 1111 never executes (spec 3.1).
`default_nettype none
module condition_checker (
    input  wire [3:0] cond_in,
    input  wire [3:0] flags_in,
    output reg        met_out
);
    wire flag_n;
    wire flag_z;
    wire flag_c;
    wire flag_v;

    assign flag_n = flags_in[3];
    assign flag_z = flags_in[2];
    assign flag_c = flags_in[1];
    assign flag_v = flags_in[0];

    always @* begin
        met_out = 1'b0;
        case (cond_in)
            4'b0000: met_out = flag_z;
            4'b0001: met_out = ~flag_z;
            4'b0010: met_out = flag_c;
            4'b0011: met_out = ~flag_c;
            4'b0100: met_out = flag_n;
            4'b0101: met_out = ~flag_n;
            4'b0110: met_out = flag_v;
            4'b0111: met_out = ~flag_v;
            4'b1000: met_out = flag_c & ~flag_z;
            4'b1001: met_out = ~flag_c | flag_z;
            4'b1010: met_out = (flag_n == flag_v);
            4'b1011: met_out = (flag_n != flag_v);
            4'b1100: met_out = ~flag_z & (flag_n == flag_v);
            4'b1101: met_out = flag_z | (flag_n != flag_v);
            4'b1110: met_out = 1'b1;
            default: met_out = 1'b0;
        endcase
    end
endmodule
`default_nettype wire
