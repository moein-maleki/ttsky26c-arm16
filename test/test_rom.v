// Test ROM for the RTL suite: same name and ports as src/demo_rom.v, but 1,024 words that cocotb
// writes by hierarchy before reset is released (plan, task 2). Not part of the design.
`default_nettype none
module demo_rom (
    input  wire [15:2] address_in,
    output wire [31:0] word_out
);
    reg [31:0] mem [0:1023];
    assign word_out = mem[address_in[11:2]];
endmodule
`default_nettype wire
