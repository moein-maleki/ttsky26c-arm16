// arm16 on TinyTapeout TTSKY26c: a 16-bit five-stage ARM pipeline that streams its program from the
// QSPI Pmod flash, keeps data in the Pmod PSRAM and shows a 16-bit value on the TinyVGA Pmod.
// Structural top: pin glue, the controller, the datapath and the reset synchronizer (docs/spec.md 7).
`default_nettype none
module tt_um_moein_maleki_arm16 (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);
    wire       rst_sync;
    wire [3:0] qspi_sd_in;
    wire [3:0] qspi_sd_out;
    wire [3:0] qspi_sd_oe;
    wire       qspi_sck;
    wire       cs_flash_n;
    wire       cs_ram_a_n;
    wire       cs_ram_b_n;
    wire [7:0] video_pins;
    wire       rom_mode;
    wire       busy;
    wire       word_valid;
    wire       data_done;
    wire       redirect;
    wire       mem_access;
    wire       mem_write;
    wire       addr_is_flash;
    wire       hazard;
    wire       stream_start;
    wire       stream_stop;
    wire       data_start;
    wire       data_flash;
    wire       data_write;
    wire       word_take;
    wire       word_room;
    wire       addr_sel;
    wire       fetch_addr_load;
    wire       fetch_addr_inc;
    wire       fetch_word_load;
    wire       fetch_src_rom;
    wire       if_id_load;
    wire       if_id_bubble;
    wire       id_ex_bubble;
    wire       mem_busy;
    wire       unused_ena;

    assign qspi_sd_in = {uio_in[5], uio_in[4], uio_in[2], uio_in[1]};
    assign uio_out    = {cs_ram_b_n, cs_ram_a_n, qspi_sd_out[3], qspi_sd_out[2], qspi_sck, qspi_sd_out[1], qspi_sd_out[0], cs_flash_n};
    assign uio_oe     = {1'b1, 1'b1, qspi_sd_oe[3], qspi_sd_oe[2], 1'b1, qspi_sd_oe[1], qspi_sd_oe[0], 1'b1};
    assign uo_out     = video_pins;
    assign unused_ena = ena & uio_in[0] & uio_in[3] & uio_in[6] & uio_in[7];

    arm16_controller arm16_controller_unit (
        .clk                 (clk),
        .rst                 (rst_sync),
        .rom_mode_in         (rom_mode),
        .busy_in             (busy),
        .word_valid_in       (word_valid),
        .data_done_in        (data_done),
        .redirect_in         (redirect),
        .mem_access_in       (mem_access),
        .mem_write_in        (mem_write),
        .addr_is_flash_in    (addr_is_flash),
        .hazard_in           (hazard),
        .stream_start_out    (stream_start),
        .stream_stop_out     (stream_stop),
        .data_start_out      (data_start),
        .data_flash_out      (data_flash),
        .data_write_out      (data_write),
        .word_take_out       (word_take),
        .word_room_out       (word_room),
        .addr_sel_out        (addr_sel),
        .fetch_addr_load_out (fetch_addr_load),
        .fetch_addr_inc_out  (fetch_addr_inc),
        .fetch_word_load_out (fetch_word_load),
        .fetch_src_rom_out   (fetch_src_rom),
        .if_id_load_out      (if_id_load),
        .if_id_bubble_out    (if_id_bubble),
        .id_ex_bubble_out    (id_ex_bubble),
        .mem_busy_out        (mem_busy)
    );

    arm16_datapath arm16_datapath_unit (
        .clk                (clk),
        .rst                (rst_sync),
        .pins_in            (ui_in),
        .qspi_sd_in         (qspi_sd_in),
        .stream_start_in    (stream_start),
        .stream_stop_in     (stream_stop),
        .data_start_in      (data_start),
        .data_flash_in      (data_flash),
        .data_write_in      (data_write),
        .word_take_in       (word_take),
        .word_room_in       (word_room),
        .addr_sel_in        (addr_sel),
        .fetch_addr_load_in (fetch_addr_load),
        .fetch_addr_inc_in  (fetch_addr_inc),
        .fetch_word_load_in (fetch_word_load),
        .fetch_src_rom_in   (fetch_src_rom),
        .if_id_load_in      (if_id_load),
        .if_id_bubble_in    (if_id_bubble),
        .id_ex_bubble_in    (id_ex_bubble),
        .mem_busy_in        (mem_busy),
        .rom_mode_out       (rom_mode),
        .busy_out           (busy),
        .word_valid_out     (word_valid),
        .data_done_out      (data_done),
        .redirect_out       (redirect),
        .mem_access_out     (mem_access),
        .mem_write_out      (mem_write),
        .addr_is_flash_out  (addr_is_flash),
        .hazard_out         (hazard),
        .video_pins_out     (video_pins),
        .qspi_sd_out        (qspi_sd_out),
        .qspi_sd_oe_out     (qspi_sd_oe),
        .qspi_sck_out       (qspi_sck),
        .cs_flash_n_out     (cs_flash_n),
        .cs_ram_a_n_out     (cs_ram_a_n),
        .cs_ram_b_n_out     (cs_ram_b_n)
    );

    reset_synchronizer reset_synchronizer_unit (
        .clk     (clk),
        .rst_n   (rst_n),
        .rst_out (rst_sync)
    );
endmodule
`default_nettype wire
