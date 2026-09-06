// Fifteen 16-bit registers, two read ports, one write port on the falling clock edge (spec 3.2).
// No reset: the general registers are unpredictable after reset (spec 10). Reads of r15 are replaced
// by PC + 8 in the datapath.
`default_nettype none
module register_file (
    input  wire        clk,
    input  wire [3:0]  read_first_addr_in,
    input  wire [3:0]  read_second_addr_in,
    input  wire        write_en_in,
    input  wire [3:0]  write_addr_in,
    input  wire [15:0] write_data_in,
    output wire [15:0] read_first_data_out,
    output wire [15:0] read_second_data_out
);
    reg [15:0] regs [0:14];

    assign read_first_data_out  = regs[read_first_addr_in];
    assign read_second_data_out = regs[read_second_addr_in];

    always @(negedge clk) begin
        if (write_en_in) begin
            regs[write_addr_in] <= write_data_in;
        end
    end
endmodule
`default_nettype wire
