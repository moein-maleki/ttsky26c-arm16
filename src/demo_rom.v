// Internal demo ROM (spec 3.5): sixteen instructions at 0x0000 to 0x003C, decoded from address bits
// [5:2]. The program counts on the screen through VGA_VAL with an eight-deep dependent chain, so the
// count rate changes about 2x with FWD_EN. Source: test/programs/demo_rom.s, encoded by test/arm16_asm.py.
`default_nettype none
module demo_rom (
    input  wire [15:2] address_in,
    output reg  [31:0] word_out
);
    always @* begin
        word_out = 32'hEAFFFFFE;
        case (address_in[5:2])
            4'd0 : word_out = 32'hE3A00000;   // MOV r0, #0
            4'd1 : word_out = 32'hE3A0A000;   // MOV r10, #0
            4'd2 : word_out = 32'hE3A01CFF;   // MOV r1, #0xFF00
            4'd3 : word_out = 32'hE2802001;   // ADD r2, r0, #1
            4'd4 : word_out = 32'hE2823001;   // ADD r3, r2, #1
            4'd5 : word_out = 32'hE2834001;   // ADD r4, r3, #1
            4'd6 : word_out = 32'hE2845001;   // ADD r5, r4, #1
            4'd7 : word_out = 32'hE2856001;   // ADD r6, r5, #1
            4'd8 : word_out = 32'hE2867001;   // ADD r7, r6, #1
            4'd9 : word_out = 32'hE2878001;   // ADD r8, r7, #1
            4'd10: word_out = 32'hE2480006;   // SUB r0, r8, #6
            4'd11: word_out = 32'hE3500000;   // CMP r0, #0
            4'd12: word_out = 32'h028AA001;   // ADDEQ r10, r10, #1
            4'd13: word_out = 32'hE581A000;   // STR r10, [r1, #0]
            4'd14: word_out = 32'hEAFFFFF3;   // B loop
            4'd15: word_out = 32'hEAFFFFFE;   // B .
            default: word_out = 32'hEAFFFFFE;
        endcase
    end
endmodule
`default_nettype wire
