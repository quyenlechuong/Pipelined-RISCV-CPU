`timescale 1ns / 1ps

module tb;

    /*************************/
    /* 1. SIGNAL DEFINITIONS */
    /*************************/
    reg clk;
    reg rst;
    wire halt;
    wire [31:0] trace_writeback_pc;
    wire [31:0] trace_writeback_inst;
    
    // Biến lưu tổng số lỗi để đánh giá toàn bộ Testbench
    integer total_errors; 

    /****************************/
    /* 2. INSTANTIATE PROCESSOR */
    /****************************/
    Processor dut (
        .clk(clk),
        .rst(rst),
        .halt(halt),
        .trace_writeback_pc(trace_writeback_pc),
        .trace_writeback_inst(trace_writeback_inst)
    );

    /***********************/
    /* 3. CLOCK GENERATION */
    /***********************/
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    always @(posedge clk) begin
        if (!rst) begin
            #1;
            $display("[TRACE] Cycle = %0d | WB PC = %h", dut.datapath.cycles_current, trace_writeback_pc);
        end
    end

    /******************************************/
    /* 4. HELPER TASK: DYNAMIC PROGRAM LOADER */
    /******************************************/
    reg [31:0] program_buffer [0:127];
    
    task load_program;
        input integer num_insts;
        integer f, i;
        begin
            f = $fopen("mem_initial_contents_test.hex", "w");
            if (f == 0) begin
                $display("[ERROR] Could not open hex file for writing!");
                $finish;
            end
            
            for (i = 0; i < num_insts; i = i + 1) begin
                $fdisplay(f, "%h", program_buffer[i]);
            end
            
            repeat(10) $fdisplay(f, "00000013"); 

            $fclose(f);
            
            $readmemh("mem_initial_contents_test.hex", dut.memory.mem_array);
        end
    endtask

    /**********************************/
    /* 5. HELPER TASK: RESULT CHECKER */
    /**********************************/
    task check_result;
        input [8*10:1] test_name;
        input integer reg_num;
        input [31:0] expected_val;
        input is_signed;
        
        reg [31:0] actual_val;
        begin
            actual_val = dut.datapath.rf.regs[reg_num];

            if (actual_val === expected_val) begin
                if (is_signed)
                    $display("[PASS] %s: x%0d = %0d (Expected %0d)", 
                             test_name, reg_num, $signed(actual_val), $signed(expected_val));
                else
                    $display("[PASS] %s: x%0d = %h (Expected %h)", 
                             test_name, reg_num, actual_val, expected_val);
            end else begin
                total_errors = total_errors + 1; // Tăng biến đếm lỗi
                if (is_signed)
                    $display("[FAIL] %s: x%0d = %0d (Expected %0d)", 
                             test_name, reg_num, $signed(actual_val), $signed(expected_val));
                else
                    $display("[FAIL] %s: x%0d = %h (Expected %h)", 
                             test_name, reg_num, actual_val, expected_val);
            end
        end
    endtask

    /*************************/
    /* 6. MAIN TEST SEQUENCE */
    /*************************/
    initial begin
        total_errors = 0; // Khởi tạo số lỗi = 0
        
        $display("/*************************************************/");
        $display("/* STARTING COMPREHENSIVE TEST BENCH (PIPELINED) */");
        $display("/*************************************************/");

        /*****************************************/
        /* PROGRAM 1: I-TYPE ARITHMETIC & SHIFTS */
        /*****************************************/
        $display("\n/*****************************************/");
        $display("/* PROGRAM 1: I-TYPE ARITHMETIC & SHIFTS */");
        $display("/*****************************************/");
        $display("[ASSEMBLY TRACE]");
        $display(" 0: ADDI  x1, x0, -1");
        $display(" 1: SLLI  x2, x1, 4");
        $display(" 2: SRLI  x3, x1, 4");
        $display(" 3: SRAI  x4, x1, 4");
        $display(" 4: XORI  x5, x1, 1");
        $display(" 5: ORI   x6, x0, 255");
        $display(" 6: ANDI  x7, x6, 15");
        $display(" 7: SLTI  x8, x1, 0");
        $display(" 8: SLTIU x9, x1, 0");
        $display(" 9: ecall");

        program_buffer[0] = 32'hfff00093;
        program_buffer[1] = 32'h00409113;
        program_buffer[2] = 32'h0040d193;
        program_buffer[3] = 32'h4040d213;
        program_buffer[4] = 32'h0010c293;
        program_buffer[5] = 32'h0ff06313;
        program_buffer[6] = 32'h00f37393;
        program_buffer[7] = 32'h0000a413;
        program_buffer[8] = 32'h0000b493;
        program_buffer[9] = 32'h00000073;

        load_program(10);
        rst = 1; #20; @(negedge clk) rst = 0;
        wait(halt); @(posedge clk); #1;
        $display("[CYCLE] Total Cycles = %0d", dut.datapath.cycles_current);
        
        check_result("ADDI ", 1, 32'hFFFFFFFF, 0); 
        check_result("SLLI ", 2, 32'hFFFFFFF0, 0);
        check_result("SRLI ", 3, 32'h0FFFFFFF, 0);
        check_result("SRAI ", 4, 32'hFFFFFFFF, 0);
        check_result("XORI ", 5, 32'hFFFFFFFE, 0);
        check_result("ORI  ", 6, 32'h000000FF, 0);
        check_result("ANDI ", 7, 32'h0000000F, 0);
        check_result("SLTI ", 8, 1, 1);           
        check_result("SLTIU", 9, 0, 1);

        /***************************************/
        /* PROGRAM 2: R-TYPE ARITHMETIC & LOGIC*/
        /***************************************/
        $display("\n/******************************************/");
        $display("/* PROGRAM 2: R-TYPE ARITHMETIC & LOGIC   */");
        $display("/******************************************/");
        $display("[ASSEMBLY TRACE]");
        $display(" 0: ADDI x1, x0, 10");
        $display(" 1: ADDI x2, x0, 3");
        $display(" 2: ADDI x3, x0, -5");
        $display(" 3: ADD  x4, x1, x2");
        $display(" 4: SUB  x5, x1, x2");
        $display(" 5: SLL  x6, x1, x2");
        $display(" 6: SLT  x7, x3, x1");
        $display(" 7: SLTU x8, x3, x1");
        $display(" 8: XOR  x9, x1, x2");
        $display(" 9: SRL  x10, x3, x2");
        $display("10: SRA  x11, x3, x2");
        $display("11: OR   x12, x1, x2");
        $display("12: AND  x13, x1, x2");
        $display("13: ecall");

        program_buffer[0] = 32'h00a00093;
        program_buffer[1] = 32'h00300113;
        program_buffer[2] = 32'hffb00193;
        program_buffer[3] = 32'h00208233;
        program_buffer[4] = 32'h402082b3;
        program_buffer[5] = 32'h00209333;
        program_buffer[6] = 32'h0011a3b3;
        program_buffer[7] = 32'h0011b433;
        program_buffer[8] = 32'h0020c4b3;
        program_buffer[9] = 32'h0021d533;
        program_buffer[10] = 32'h4021d5b3;
        program_buffer[11] = 32'h0020e633;
        program_buffer[12] = 32'h0020f6b3;
        program_buffer[13] = 32'h00000073;

        load_program(14);
        rst = 1; #20; @(negedge clk) rst = 0;
        wait(halt); @(posedge clk); #1;
        $display("[CYCLE] Total Cycles = %0d", dut.datapath.cycles_current);

        check_result("ADD  ", 4, 13, 1);
        check_result("SUB  ", 5, 7, 1);
        check_result("SLL  ", 6, 80, 1);
        check_result("SLT  ", 7, 1, 1);
        check_result("SLTU ", 8, 0, 1);
        check_result("XOR  ", 9, 9, 1);
        check_result("SRL  ", 10, 32'h1FFFFFFF, 0);
        check_result("SRA  ", 11, 32'hFFFFFFFF, 0);
        check_result("OR   ", 12, 11, 1);
        check_result("AND  ", 13, 2, 1);

        /**************************************/
        /* PROGRAM 3: BRANCHES, JUMPS & LUI   */
        /**************************************/
        $display("\n/**************************************/");
        $display("/* PROGRAM 3: BRANCHES, JUMPS & LUI   */");
        $display("/**************************************/");
        $display("[ASSEMBLY TRACE]");
        $display(" 0: LUI  x1, 0x12345");
        $display(" 1: ADDI x2, x0, 10");
        $display(" 2: ADDI x3, x0, 20");
        $display(" 3: BEQ  x2, x3, FAIL");
        $display(" 4: BNE  x2, x3, NEXT");
        $display(" 5: BLT  x2, x3, NEXT");
        $display(" 6: FAIL: ADDI x4, x0, -85");
        $display(" 7: BGE  x3, x2, NEXT");
        $display(" 8: FAIL: ADDI x4, x0, -85");
        $display(" 9: BLTU x2, x3, NEXT");
        $display("10: FAIL: ADDI x4, x0, -85");
        $display("11: BGEU x3, x2, NEXT");
        $display("12: FAIL: ADDI x4, x0, -85");
        $display("13: JAL  x5, SKIP");
        $display("14: NOP");
        $display("15: SKIP: ADDI x6, x0, 4");
        $display("16: ADDI x4, x0, 1");
        $display("17: ecall");

        program_buffer[0] = 32'h123450b7;
        program_buffer[1] = 32'h00a00113;
        program_buffer[2] = 32'h01400193;
        program_buffer[3] = 32'h00310463;
        program_buffer[4] = 32'h00211263;
        program_buffer[5] = 32'h00314463;
        program_buffer[6] = 32'hbad00213;
        program_buffer[7] = 32'h0021d463;
        program_buffer[8] = 32'hbad00213;
        program_buffer[9] = 32'h00316463;
        program_buffer[10] = 32'hbad00213;
        program_buffer[11] = 32'h0021f463;
        program_buffer[12] = 32'hbad00213;
        program_buffer[13] = 32'h008002ef;
        program_buffer[14] = 32'h00000013;
        program_buffer[15] = 32'h00400313;
        program_buffer[16] = 32'h00100213;
        program_buffer[17] = 32'h00000073;

        load_program(18);
        rst = 1; #20; @(negedge clk) rst = 0;
        wait(halt); @(posedge clk); #1;
        $display("[CYCLE] Total Cycles = %0d", dut.datapath.cycles_current);

        check_result("LUI  ", 1, 32'h12345000, 0);
        check_result("Branch", 4, 1, 1); 

        /**********************************/
        /* PROGRAM 4: MEMORY WIDTHS       */
        /**********************************/
        $display("\n/**********************************/");
        $display("/* PROGRAM 4: MEMORY WIDTHS       */");
        $display("/**********************************/");
        $display("[ASSEMBLY TRACE]");
        $display(" 0: ADDI x1, x0, 100");
        $display(" 1: LUI  x2, 0xDEADC");
        $display(" 2: ADDI x2, x2, 0xEEF");
        $display(" 3: SW   x2, 0(x1)");
        $display(" 4: SB   x2, 4(x1)");
        $display(" 5: SH   x2, 8(x1)");
        $display(" 6: LW   x3, 0(x1)");
        $display(" 7: LB   x4, 0(x1)");
        $display(" 8: LBU  x5, 0(x1)");
        $display(" 9: LH   x6, 0(x1)");
        $display("10: LHU  x7, 0(x1)");
        $display("11: ecall");

        program_buffer[0] = 32'h06400093;
        program_buffer[1] = 32'hdeadc137;
        program_buffer[2] = 32'heef10113;
        program_buffer[3] = 32'h0020a023;
        program_buffer[4] = 32'h00208223;
        program_buffer[5] = 32'h00209423;
        program_buffer[6] = 32'h0000a183;
        program_buffer[7] = 32'h00008203;
        program_buffer[8] = 32'h0000c283;
        program_buffer[9] = 32'h00009303;
        program_buffer[10] = 32'h0000d383;
        program_buffer[11] = 32'h00000073;

        load_program(12);
        rst = 1; #20; @(negedge clk) rst = 0;
        wait(halt); @(posedge clk); #1;
        $display("[CYCLE] Total Cycles = %0d", dut.datapath.cycles_current);

        check_result("SW/LW", 3, 32'hDEADBEEF, 0);
        check_result("LB   ", 4, 32'hFFFFFFEF, 0);
        check_result("LBU  ", 5, 32'h000000EF, 0);
        check_result("LH   ", 6, 32'hFFFFBEEF, 0);
        check_result("LHU  ", 7, 32'h0000BEEF, 0);

        /**********************************/
        /* PROGRAM 5: M-EXTENSION SUITE   */
        /**********************************/
        $display("\n/**********************************/");
        $display("/* PROGRAM 5: M-EXTENSION SUITE   */");
        $display("/**********************************/");
        $display("[ASSEMBLY TRACE]");
        $display(" 0: ADDI x1, x0, 20");
        $display(" 1: ADDI x2, x0, -5");
        $display(" 2: ADDI x3, x0, 30");
        $display(" 3: MUL  x4, x1, x2");
        $display(" 4: MULH x5, x1, x2");
        $display(" 5: DIV  x6, x1, x2");
        $display(" 6: REM  x7, x1, x2");
        $display(" 7: DIVU x8, x3, x1");
        $display(" 8: REMU x9, x3, x1");
        $display(" 9: ecall");

        program_buffer[0] = 32'h01400093;
        program_buffer[1] = 32'hffb00113;
        program_buffer[2] = 32'h01e00193;
        program_buffer[3] = 32'h02208233;
        program_buffer[4] = 32'h022092b3;
        program_buffer[5] = 32'h0220c333;
        program_buffer[6] = 32'h0220e3b3;
        program_buffer[7] = 32'h0230d433;
        program_buffer[8] = 32'h0230f4b3;
        program_buffer[9] = 32'h00000073;

        load_program(10);
        rst = 1; #20; @(negedge clk) rst = 0;
        wait(halt); @(posedge clk); #1;
        $display("[CYCLE] Total Cycles = %0d", dut.datapath.cycles_current);

        check_result("MUL  ", 4, -100, 1);
        check_result("MULH ", 5, -1, 1);
        check_result("DIV  ", 6, -4, 1);
        check_result("REM  ", 7, 0, 1);
        check_result("DIVU ", 8, 0, 1);
        check_result("REMU ", 9, 20, 1);

        /**********************************/
        /* PROGRAM 6: LOAD-TO-USE HAZARD  */
        /**********************************/
        $display("\n/**********************************/");
        $display("/* PROGRAM 6: LOAD-TO-USE HAZARD  */");
        $display("/**********************************/");
        $display("[ASSEMBLY TRACE]");
        $display(" 0: ADDI x1, x0, 100");
        $display(" 1: ADDI x2, x0, 55");
        $display(" 2: SW   x2, 0(x1)");
        $display(" 3: LW   x3, 0(x1)");
        $display(" 4: ADD  x4, x3, x3");
        $display(" 5: ecall");

        program_buffer[0] = 32'h06400093;
        program_buffer[1] = 32'h03700113;
        program_buffer[2] = 32'h0020a023;
        program_buffer[3] = 32'h0000a183;
        program_buffer[4] = 32'h00318233;
        program_buffer[5] = 32'h00000073;

        load_program(6);
        rst = 1; #20; @(negedge clk) rst = 0;
        wait(halt); @(posedge clk); #1;
        $display("[CYCLE] Total Cycles = %0d", dut.datapath.cycles_current);

        check_result("L2U_ADD", 4, 110, 1);
        
        /**********************************/
        /* PROGRAM 7: ADVANCED FORWARDING */
        /**********************************/
        $display("\n/**********************************/");
        $display("/* PROGRAM 7: ADVANCED FORWARDING */");
        $display("/**********************************/");
        $display("[ASSEMBLY TRACE]");
        $display(" 0: ADDI x1, x0, 5");
        $display(" 1: ADD  x2, x1, x1");
        $display(" 2: NOP");
        $display(" 3: ADD  x3, x2, x2");
        $display(" 4: NOP");
        $display(" 5: NOP");
        $display(" 6: ADD  x4, x3, x3");
        $display(" 7: ecall");

        program_buffer[0] = 32'h00500093;
        program_buffer[1] = 32'h00108133;
        program_buffer[2] = 32'h00000013;
        program_buffer[3] = 32'h002101b3;
        program_buffer[4] = 32'h00000013;
        program_buffer[5] = 32'h00000013;
        program_buffer[6] = 32'h00318233;
        program_buffer[7] = 32'h00000073;

        load_program(8);
        rst = 1; #20; @(negedge clk) rst = 0;
        wait(halt); @(posedge clk); #1;
        $display("[CYCLE] Total Cycles = %0d", dut.datapath.cycles_current);

        check_result("FWD_EX ", 2, 10, 1);
        check_result("FWD_MEM", 3, 20, 1);
        check_result("FWD_WB ", 4, 40, 1);
        
        /**********************************/
        /* PROGRAM 8: AUIPC & JALR HAZARD */
        /**********************************/
        $display("\n/**********************************/");
        $display("/* PROGRAM 8: AUIPC & JALR HAZARD */");
        $display("/**********************************/");
        $display("[ASSEMBLY TRACE]");
        $display(" 0: AUIPC x1, 0");
        $display(" 1: JALR  x2, 12(x1)");
        $display(" 2: ADDI  x3, x0, 99");
        $display(" 3: ADDI  x4, x0, 42");
        $display(" 4: ecall");

        program_buffer[0] = 32'h00000097;
        program_buffer[1] = 32'h00c08167;
        program_buffer[2] = 32'h06300193;
        program_buffer[3] = 32'h02a00213;
        program_buffer[4] = 32'h00000073;

        load_program(5);
        rst = 1; #20; @(negedge clk) rst = 0;
        wait(halt); @(posedge clk); #1;
        $display("[CYCLE] Total Cycles = %0d", dut.datapath.cycles_current);

        check_result("JALR_RA", 2, 8, 1); 
        check_result("FLUSH  ", 3, 0, 1); 
        check_result("TARGET ", 4, 42, 1); 

        /**********************************/
        /* PROGRAM 9: ZERO REGISTER LOCK  */
        /**********************************/
        $display("\n/**********************************/");
        $display("/* PROGRAM 9: ZERO REGISTER LOCK  */");
        $display("/**********************************/");
        $display("[ASSEMBLY TRACE]");
        $display(" 0: ADDI x0, x0, 100");
        $display(" 1: ADD  x1, x0, x0");
        $display(" 2: ecall");

        program_buffer[0] = 32'h06400013;
        program_buffer[1] = 32'h000000b3;
        program_buffer[2] = 32'h00000073;

        load_program(3);
        rst = 1; #20; @(negedge clk) rst = 0;
        wait(halt); @(posedge clk); #1;
        $display("[CYCLE] Total Cycles = %0d", dut.datapath.cycles_current);

        check_result("ZERO_X1", 1, 0, 1); 
        
        /**********************************/
        /* PROGRAM 10: LOAD-TO-BRANCH     */
        /**********************************/
        $display("\n/**********************************/");
        $display("/* PROGRAM 10: LOAD-TO-BRANCH     */");
        /**********************************/
        $display("[ASSEMBLY TRACE]");
        $display(" 0: ADDI x1, x0, 100");
        $display(" 1: ADDI x2, x0, 10");
        $display(" 2: SW   x2, 0(x1)");
        $display(" 3: LW   x3, 0(x1)");
        $display(" 4: BEQ  x3, x2, 8");
        $display(" 5: ADDI x4, x0, 99");
        $display(" 6: ADDI x4, x0, 1");
        $display(" 7: ecall");

        program_buffer[0] = 32'h06400093;
        program_buffer[1] = 32'h00a00113;
        program_buffer[2] = 32'h0020a023;
        program_buffer[3] = 32'h0000a183;
        program_buffer[4] = 32'h00218463;
        program_buffer[5] = 32'h06300213;
        program_buffer[6] = 32'h00100213;
        program_buffer[7] = 32'h00000073;

        load_program(8);
        rst = 1; #20; @(negedge clk) rst = 0;
        wait(halt); @(posedge clk); #1;
        $display("[CYCLE] Total Cycles = %0d", dut.datapath.cycles_current);

        check_result("L2B_TGT", 4, 1, 1); 

        /**********************************/
        /* FINAL TEST RESULT SUMMARY      */
        /**********************************/
        $display("\n/**************************************************/");
        if (total_errors == 0) begin
            $display("/* ALL TESTS PASSED SUCCESSFULLY!                 */");
        end else begin
            $display("/* SIMULATION FAILED WITH %0d ERRORS!               */", total_errors);
        end
        $display("/**************************************************/");
        
        $finish;
    end

endmodule