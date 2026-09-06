module register_file(
    input               clk,
    input               rst,
    input       [3:0]   read_src_1_reg,
    input       [3:0]   read_src_2_reg,
    input       [3:0]   write_src_reg,
    input               wb_en,
    input       [31:0]  wb_value,

    output      [31:0]  read_src_1_data,
    output      [31:0]  read_src_2_data
);
    reg         [31:0]  register_file_data [14:0];

    integer i = 0;

    initial begin
        for(i = 0; i < 15; i=i+1) begin
            register_file_data[i] = i;
        end
    end

    assign read_src_1_data = register_file_data[read_src_1_reg];
    assign read_src_2_data = register_file_data[read_src_2_reg];

    always @(negedge clk) begin
        if(wb_en) register_file_data[write_src_reg] <= wb_value;
        else register_file_data[write_src_reg] <= register_file_data[write_src_reg];
    end

endmodule