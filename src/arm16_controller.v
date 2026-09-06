// arm16 controller (docs/spec.md 3.2, 3.3): the fetch and bus sequencer and the pipeline flow control.
// States: S_IDLE (between transactions), S_ROM (internal ROM mode, never left), S_STREAM_EMPTY (flash
// stream open, no delivered word), S_STREAM_FULL (a delivered word waits for the pipeline), S_DATA
// (a data transaction runs, the pipeline is frozen). The fetch address advances exactly once per
// accepted word; every abort restarts the stream at the fetch address (plan D3).
`default_nettype none
module arm16_controller (
    input  wire clk,
    input  wire rst,
    input  wire rom_mode_in,
    input  wire busy_in,
    input  wire word_valid_in,
    input  wire data_done_in,
    input  wire redirect_in,
    input  wire mem_access_in,
    input  wire mem_write_in,
    input  wire addr_is_flash_in,
    input  wire hazard_in,
    output reg  stream_start_out,
    output reg  stream_stop_out,
    output reg  data_start_out,
    output reg  data_flash_out,
    output reg  data_write_out,
    output reg  word_take_out,
    output reg  word_room_out,
    output reg  addr_sel_out,
    output reg  fetch_addr_load_out,
    output reg  fetch_addr_inc_out,
    output reg  fetch_word_load_out,
    output reg  fetch_src_rom_out,
    output reg  if_id_load_out,
    output reg  if_id_bubble_out,
    output reg  id_ex_bubble_out,
    output reg  mem_busy_out
);
    localparam [2:0] S_IDLE         = 3'd0;
    localparam [2:0] S_ROM          = 3'd1;
    localparam [2:0] S_STREAM_EMPTY = 3'd2;
    localparam [2:0] S_STREAM_FULL  = 3'd3;
    localparam [2:0] S_DATA         = 3'd4;

    wire mem_busy;
    wire fetch_ready;
    wire abort;

    reg [2:0] present_state;
    reg [2:0] next_state;

    assign mem_busy    = mem_access_in & (present_state != S_ROM) & ~((present_state == S_DATA) & data_done_in);
    assign fetch_ready = ~hazard_in & ~mem_busy;
    assign abort       = redirect_in | mem_access_in;

    always @(posedge clk) begin
        if (rst) begin
            present_state <= S_IDLE;
        end else begin
            present_state <= next_state;
        end
    end

    always @* begin
        next_state = present_state;
        case (present_state)
            S_IDLE: begin
                if (rom_mode_in) begin
                    next_state = S_ROM;
                end else if (mem_access_in & ~busy_in) begin
                    next_state = S_DATA;
                end else if (~busy_in & ~redirect_in) begin
                    next_state = S_STREAM_EMPTY;
                end
            end
            S_ROM: begin
                next_state = S_ROM;
            end
            S_STREAM_EMPTY: begin
                if (abort) begin
                    next_state = S_IDLE;
                end else if (word_valid_in) begin
                    next_state = S_STREAM_FULL;
                end
            end
            S_STREAM_FULL: begin
                if (abort) begin
                    next_state = S_IDLE;
                end else if (fetch_ready & ~word_valid_in) begin
                    next_state = S_STREAM_EMPTY;
                end
            end
            S_DATA: begin
                if (data_done_in) begin
                    next_state = S_IDLE;
                end
            end
            default: begin
                next_state = S_IDLE;
            end
        endcase
    end

    always @* begin
        stream_start_out    = 1'b0;
        stream_stop_out     = 1'b0;
        data_start_out      = 1'b0;
        data_flash_out      = addr_is_flash_in;
        data_write_out      = mem_write_in;
        word_take_out       = 1'b0;
        word_room_out       = 1'b0;
        addr_sel_out        = 1'b0;
        fetch_addr_load_out = redirect_in;
        fetch_addr_inc_out  = 1'b0;
        fetch_word_load_out = 1'b0;
        fetch_src_rom_out   = 1'b0;
        if_id_load_out      = 1'b0;
        if_id_bubble_out    = fetch_ready | redirect_in;
        id_ex_bubble_out    = hazard_in | redirect_in;
        mem_busy_out        = mem_busy;
        case (present_state)
            S_IDLE: begin
                if (~rom_mode_in & mem_access_in & ~busy_in) begin
                    data_start_out = 1'b1;
                    addr_sel_out   = 1'b1;
                end else if (~rom_mode_in & ~busy_in & ~redirect_in) begin
                    stream_start_out = 1'b1;
                end
            end
            S_ROM: begin
                fetch_src_rom_out  = 1'b1;
                if_id_load_out     = fetch_ready & ~redirect_in;
                if_id_bubble_out   = redirect_in;
                fetch_addr_inc_out = fetch_ready & ~redirect_in;
            end
            S_STREAM_EMPTY: begin
                stream_stop_out     = abort;
                word_room_out       = ~abort;
                word_take_out       = word_valid_in & ~abort;
                fetch_word_load_out = word_valid_in & ~abort;
            end
            S_STREAM_FULL: begin
                stream_stop_out     = abort;
                word_room_out       = fetch_ready & ~abort;
                word_take_out       = word_valid_in & fetch_ready & ~abort;
                fetch_word_load_out = word_valid_in & fetch_ready & ~abort;
                if_id_load_out      = fetch_ready & ~redirect_in;
                if_id_bubble_out    = redirect_in;
                fetch_addr_inc_out  = fetch_ready & ~redirect_in;
            end
            S_DATA: begin
                addr_sel_out = 1'b1;
            end
            default: begin
                stream_start_out = 1'b0;
            end
        endcase
    end
endmodule
`default_nettype wire
