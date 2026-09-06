// QSPI engine (spec 3.3). Sprint task 4 replaces this idle stub with the streaming engine; the
// interface is final. Idle: chip selects high, SCK low, data pins as inputs, no word ever valid.
`default_nettype none
module qspi_master #(
    parameter TICK_RATIO = 2,
    parameter CS_LOW_MAX = 150,
    parameter GAP_CYCLES = 2
) (
    input  wire        clk,
    input  wire        rst,
    input  wire [1:0]  rx_delay_in,
    input  wire        stream_start_in,
    input  wire        stream_stop_in,
    input  wire        data_start_in,
    input  wire        data_flash_in,
    input  wire        data_write_in,
    input  wire [15:0] addr_in,
    input  wire [15:0] wdata_in,
    input  wire        word_take_in,
    input  wire        word_room_in,
    input  wire [3:0]  sd_in,
    output wire        busy_out,
    output wire        word_valid_out,
    output wire        data_done_out,
    output wire [31:0] rdata_out,
    output wire        fault_out,
    output wire        sck_out,
    output wire        cs_flash_n_out,
    output wire        cs_ram_a_n_out,
    output wire        cs_ram_b_n_out,
    output wire [3:0]  sd_out,
    output wire [3:0]  sd_oe_out
);
    assign busy_out       = 1'b0;
    assign word_valid_out = 1'b0;
    assign data_done_out  = data_start_in;
    assign rdata_out      = 32'h0000_0000;
    assign fault_out      = 1'b0;
    assign sck_out        = 1'b0;
    assign cs_flash_n_out = 1'b1;
    assign cs_ram_a_n_out = 1'b1;
    assign cs_ram_b_n_out = 1'b1;
    assign sd_out         = 4'b0000;
    assign sd_oe_out      = 4'b0000;
endmodule
`default_nettype wire
