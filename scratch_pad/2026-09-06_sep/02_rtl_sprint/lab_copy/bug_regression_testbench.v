`timescale 1ns/1ps

module bug_regression_testbench;

    reg             clk;
    reg             rst;
    reg             use_forwarding;
    integer         failure_count;

    reg     [3:0]   instr_condition;
    reg     [3:0]   status_register;
    wire            condition_is_met;
    reg     [31:0]  alu_in_1;
    reg     [31:0]  alu_in_2;
    reg     [3:0]   execute_command;
    reg     [3:0]   status_bits_in;
    wire    [31:0]  alu_result;
    wire    [3:0]   status_bits_out;
    reg             branch_taken_in;
    reg             freeze_in;
    reg     [31:0]  branch_address_in;
    wire    [31:0]  pc_plus_four_out;
    reg     [31:0]  instruction_in;
    wire            wb_en_out;
    wire            mem_r_en_out;
    wire            branch_taken_out;
    wire            do_update_sr_out;
    wire            instr_has_src2_out;
    wire            hazard_two_src_out;

    always #5 clk = ~clk;

    condition_check condition_check_unit (
        .instr_condition    (instr_condition),
        .status_register    (status_register),
        .condition_is_met   (condition_is_met)
    );

    alu alu_unit (
        .alu_in_1           (alu_in_1),
        .alu_in_2           (alu_in_2),
        .execute_command    (execute_command),
        .status_bits_in     (status_bits_in),
        .alu_result         (alu_result),
        .status_bits_out    (status_bits_out)
    );

    IF_stage if_stage_unit (
        .clk                (clk),
        .rst                (rst),
        .branch_taken_in    (branch_taken_in),
        .freeze_in          (freeze_in),
        .branch_address_in  (branch_address_in),
        .pc_plus_four_out   (pc_plus_four_out)
    );

    ID_stage id_stage_unit (
        .clk                    (clk),
        .rst                    (rst),
        .hazard_in              (1'b0),
        .wb_dest_in             (4'b0),
        .wb_value_in            (32'b0),
        .wb_wb_en_in            (1'b0),
        .instruction_in         (instruction_in),
        .status_bits_in         (4'b0),
        .pc_plus_four_in        (32'b0),
        .wb_en_out              (wb_en_out),
        .mem_r_en_out           (mem_r_en_out),
        .branch_taken_out       (branch_taken_out),
        .do_update_sr_out       (do_update_sr_out),
        .instr_has_src2_out     (instr_has_src2_out),
        .hazard_two_src_out     (hazard_two_src_out)
    );

    arm_processor processor_unit (
        .clk                (clk),
        .rst                (rst),
        .use_forwarding     (use_forwarding)
    );

    task check;
        input                   condition;
        input [8*96-1:0]        check_name;
        begin
            if (condition !== 1'b1) begin
                failure_count = failure_count + 1;
                $display("FAIL: %0s", check_name);
            end
            else begin
                $display("PASS: %0s", check_name);
            end
        end
    endtask

    initial begin
        clk                 = 1'b0;
        rst                 = 1'b1;
        use_forwarding      = 1'b1;
        failure_count       = 0;
        instr_condition     = 4'b1001;
        status_register     = 4'b0000;
        alu_in_1            = 32'b0;
        alu_in_2            = 32'b0;
        execute_command     = 4'b0001;
        status_bits_in      = 4'b0;
        branch_taken_in     = 1'b0;
        freeze_in           = 1'b0;
        branch_address_in   = 32'b0;
        instruction_in      = 32'he091_2003;

        #1;
        check(condition_is_met === 1'b1, "LS is true when C=0 and Z=0");
        status_register = 4'b0100;
        #1;
        check(condition_is_met === 1'b1, "LS is true when C=0 and Z=1");
        status_register = 4'b0010;
        #1;
        check(condition_is_met === 1'b0, "LS is false when C=1 and Z=0");
        status_register = 4'b0110;
        #1;
        check(condition_is_met === 1'b1, "LS is true when C=1 and Z=1");

        alu_in_2        = 32'h0000_0005;
        execute_command = 4'b0001;
        status_bits_in  = 4'b0000;
        #1;
        check((alu_result === 32'h0000_0005) && (status_bits_out[1] === 1'b0),
              "MOV preserves input carry zero");
        alu_in_1        = 32'h0000_0001;
        alu_in_2        = 32'h0000_0001;
        execute_command = 4'b0010;
        #1;
        check((alu_result === 32'h0000_0002) && (status_bits_out[1] === 1'b0),
              "ADD produces carry zero");
        execute_command = 4'b0111;
        status_bits_in  = 4'b0010;
        #1;
        check((alu_result === 32'h0000_0001) && (status_bits_out[1] === 1'b1),
              "ORR preserves input carry one");
        execute_command = 4'b1111;
        status_bits_in  = 4'b0000;
        #1;
        check(status_bits_out[1] === 1'b0,
              "default ALU command preserves input carry zero");
        execute_command = 4'b0000;
        status_bits_in  = 4'b0010;
        #1;
        check((alu_result === 32'b0) && (status_bits_out[1] === 1'b1),
              "NOP preserves input carry one");

        instruction_in = 32'he491_2000;
        #1;
        check((wb_en_out === 1'b1) && (mem_r_en_out === 1'b1),
              "LDR keeps its write and memory-read controls");
        check(do_update_sr_out === 1'b0, "LDR does not update status flags");
        check((instr_has_src2_out === 1'b0) && (hazard_two_src_out === 1'b0),
              "LDR offset bits do not create a false source-two hazard");
        instruction_in = 32'hea10_0000;
        #1;
        check(branch_taken_out === 1'b1, "branch instruction remains accepted");
        check(do_update_sr_out === 1'b0, "branch immediate bit 20 does not update status flags");
        instruction_in = 32'he091_2003;
        #1;
        check(do_update_sr_out === 1'b1, "ADDS updates status flags");

        force processor_unit.id_out_hazard_src1      = 4'd7;
        force processor_unit.id_out_hazard_src2      = 4'd0;
        force processor_unit.id_out_hazard_two_src   = 1'b0;
        force processor_unit.id_out_instr_has_src1   = 1'b1;
        force processor_unit.exe_out_wb_en           = 1'b1;
        force processor_unit.exe_out_wb_reg_dest     = 4'd7;
        force processor_unit.mem_out_wb_en           = 1'b0;
        force processor_unit.mem_out_wb_reg_dest     = 4'd0;
        force processor_unit.exe_out_mem_r_en        = 1'b1;
        force processor_unit.mem_in_mem_r_en         = 1'b0;
        #1;
        check(processor_unit.hazard_out_hazard === 1'b1,
              "dependent instruction stalls while its load is in EXE");
        force processor_unit.id_out_hazard_src1      = 4'd6;
        #1;
        check(processor_unit.hazard_out_hazard === 1'b0,
              "independent instruction does not stall for an EXE load");
        force processor_unit.exe_out_mem_r_en        = 1'b0;
        force processor_unit.mem_in_mem_r_en         = 1'b1;
        #1;
        check(processor_unit.hazard_out_hazard === 1'b0,
              "a load in MEM does not cause a late forwarding stall");

        @(posedge clk);
        #1;
        @(negedge clk);
        rst                 = 1'b0;
        branch_taken_in     = 1'b1;
        freeze_in           = 1'b1;
        branch_address_in   = 32'd100;
        @(posedge clk);
        #1;
        check(pc_plus_four_out === 32'd104,
              "branch address has priority over a simultaneous freeze");
        branch_taken_in = 1'b0;
        @(posedge clk);
        #1;
        check(pc_plus_four_out === 32'd104, "freeze holds the branch target");
        @(negedge clk);
        freeze_in = 1'b0;
        @(posedge clk);
        #1;
        check(pc_plus_four_out === 32'd108, "PC resumes after the freeze ends");

        if (failure_count != 0)
            $fatal(1, "%0d directed checks failed", failure_count);

        $display("PASS: all directed checks passed");
        $finish;
    end

endmodule
