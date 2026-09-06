// Stall decision in the decode stage (spec 3.2). Forwarding on: one bubble when a load in execute
// writes a register the decode instruction reads. Forwarding off: a bubble while any instruction in
// execute or memory writes a register the decode instruction reads.
`default_nettype none
module hazard_detector (
    input  wire       fwd_en_in,
    input  wire       id_valid_in,
    input  wire [3:0] id_src1_in,
    input  wire [3:0] id_src2_in,
    input  wire       id_has_src1_in,
    input  wire       id_has_src2_in,
    input  wire       ex_wb_en_in,
    input  wire [3:0] ex_dest_in,
    input  wire       ex_mem_read_in,
    input  wire       mem_wb_en_in,
    input  wire [3:0] mem_dest_in,
    output wire       hazard_out
);
    wire src1_live;
    wire src2_live;
    wire ex_match;
    wire mem_match;

    assign src1_live = id_valid_in & id_has_src1_in;
    assign src2_live = id_valid_in & id_has_src2_in;
    assign ex_match  = ex_wb_en_in & ((src1_live & (ex_dest_in == id_src1_in)) | (src2_live & (ex_dest_in == id_src2_in)));
    assign mem_match = mem_wb_en_in & ((src1_live & (mem_dest_in == id_src1_in)) | (src2_live & (mem_dest_in == id_src2_in)));
    assign hazard_out = fwd_en_in ? (ex_match & ex_mem_read_in) : (ex_match | mem_match);
endmodule
`default_nettype wire
