`timescale 1ns/1ns

module testbench;

    reg duv_clk;
    reg duv_rst;
    reg duv_use_forwarding;
    
    arm_processor DUV (
        .clk                (duv_clk),
        .rst                (duv_rst),
        .use_forwarding     (duv_use_forwarding)
    );

    always #10 duv_clk = ~duv_clk;

    initial begin
        duv_rst = 0;
        duv_clk = 0;
        duv_use_forwarding = 1;

        @(posedge duv_clk) duv_rst = 1;
        @(posedge duv_clk) duv_rst = 0;

        repeat(500) @(posedge duv_clk) ;
        $stop();
    end

endmodule