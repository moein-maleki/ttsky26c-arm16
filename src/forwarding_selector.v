// Operand source selection in execute: 00 register file, 01 the memory stage result, 10 the write-back
// value; the memory stage has priority. Forwarding off forces the register file.
`default_nettype none
module forwarding_selector (
    input  wire       fwd_en_in,
    input  wire [3:0] ex_src1_in,
    input  wire [3:0] ex_src2_in,
    input  wire       ex_has_src1_in,
    input  wire       ex_has_src2_in,
    input  wire       mem_wb_en_in,
    input  wire [3:0] mem_dest_in,
    input  wire       wb_wb_en_in,
    input  wire [3:0] wb_dest_in,
    output reg  [1:0] sel1_out,
    output reg  [1:0] sel2_out
);
    always @* begin
        sel1_out = 2'b00;
        sel2_out = 2'b00;
        if (fwd_en_in) begin
            if (ex_has_src1_in & mem_wb_en_in & (mem_dest_in == ex_src1_in)) begin
                sel1_out = 2'b01;
            end else if (ex_has_src1_in & wb_wb_en_in & (wb_dest_in == ex_src1_in)) begin
                sel1_out = 2'b10;
            end
            if (ex_has_src2_in & mem_wb_en_in & (mem_dest_in == ex_src2_in)) begin
                sel2_out = 2'b01;
            end else if (ex_has_src2_in & wb_wb_en_in & (wb_dest_in == ex_src2_in)) begin
                sel2_out = 2'b10;
            end
        end
    end
endmodule
`default_nettype wire
