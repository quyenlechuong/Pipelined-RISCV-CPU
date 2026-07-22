`timescale 1ns / 1ns

`define REG_SIZE 31
`define INST_SIZE 31
`define DIVIDER_STAGES 8

/***********************/
/* OPCODE DEFINITIONS */
/***********************/
`define OPC_LOAD     7'b00_000_11
`define OPC_STORE    7'b01_000_11
`define OPC_BRANCH   7'b11_000_11
`define OPC_JALR     7'b11_001_11
`define OPC_MISCMEM  7'b00_011_11
`define OPC_JAL      7'b11_011_11
`define OPC_REG_IMM  7'b00_100_11
`define OPC_REG_REG  7'b01_100_11
`define OPC_ENVIRON  7'b11_100_11
`define OPC_AUIPC    7'b00_101_11
`define OPC_LUI      7'b01_101_11

/***************************/
/* 1. MODULE DECODE UNIT   */
/***************************/
module Decode_Unit (
    input  [`INST_SIZE:0] inst,
    output [6:0] opcode,
    output [2:0] funct3,
    output [6:0] funct7,
    output [4:0] rs1,
    output [4:0] rs2,
    output [4:0] rd,
    output reg [31:0] imm,
    output reg ctrl_reg_write,
    output reg ctrl_mem_read,
    output reg ctrl_mem_write,
    output reg ctrl_branch,
    output reg ctrl_jump,
    output reg ctrl_halt
);
    assign opcode = inst[6:0];
    assign rs1    = inst[19:15];
    assign rs2    = inst[24:20];
    assign rd     = inst[11:7];
    assign funct3 = inst[14:12];
    assign funct7 = inst[31:25];

    // Immediate generation
    wire [31:0] imm_I = {{20{inst[31]}}, inst[31:20]};
    wire [31:0] imm_S = {{20{inst[31]}}, inst[31:25], inst[11:7]};
    wire [31:0] imm_B = {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
    wire [31:0] imm_U = {inst[31:12], 12'b0};
    wire [31:0] imm_J = {{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0};

    always @(*) begin
        case (opcode)
            `OPC_STORE:           imm = imm_S;
            `OPC_BRANCH:          imm = imm_B;
            `OPC_LUI, `OPC_AUIPC: imm = imm_U;
            `OPC_JAL:             imm = imm_J;
            default:              imm = imm_I;
        endcase

        // Control Signals
        ctrl_reg_write = (opcode != `OPC_STORE) && (opcode != `OPC_BRANCH) && (opcode != `OPC_ENVIRON);
        ctrl_mem_read  = (opcode == `OPC_LOAD);
        ctrl_mem_write = (opcode == `OPC_STORE);
        ctrl_branch    = (opcode == `OPC_BRANCH);
        ctrl_jump      = (opcode == `OPC_JAL) || (opcode == `OPC_JALR);
        ctrl_halt      = (opcode == `OPC_ENVIRON) && (inst[31:7] == 0);
    end
endmodule

/******************************/
/* 2. MODULE HAZARD DETECTION */
/******************************/
module Hazard_Detection (
    input [4:0] id_rs1,
    input [4:0] id_rs2,
    input [4:0] id_rd,
    input x_is_div,
    input ex_mem_read,
    input [4:0] ex_rd,
    input x_is_branch_taken,
    input [4:0] div_rd_1, div_rd_2, div_rd_3, div_rd_4, div_rd_5, div_rd_6, div_rd_7, div_rd_8,
    input div_v_1, div_v_2, div_v_3, div_v_4, div_v_5, div_v_6, div_v_7, div_v_8,
    output reg stall,
    output reg flush_if_id,
    output reg flush_id_ex
);
    always @(*) begin
        stall = 1'b0;

        // 1. Load-Use Hazard Detection
        if (ex_mem_read && (ex_rd != 0) && ((ex_rd == id_rs1) || (ex_rd == id_rs2))) begin
            stall = 1'b1;
        end

        if (id_rs1 != 0 && (
            (x_is_div && ex_rd == id_rs1) ||
            (div_v_1 && div_rd_1 == id_rs1) || (div_v_2 && div_rd_2 == id_rs1) ||
            (div_v_3 && div_rd_3 == id_rs1) || (div_v_4 && div_rd_4 == id_rs1) ||
            (div_v_5 && div_rd_5 == id_rs1) || (div_v_6 && div_rd_6 == id_rs1) ||
            (div_v_7 && div_rd_7 == id_rs1) || (div_v_8 && div_rd_8 == id_rs1)
        )) stall = 1'b1;

        if (id_rs2 != 0 && (
            (x_is_div && ex_rd == id_rs2) ||
            (div_v_1 && div_rd_1 == id_rs2) || (div_v_2 && div_rd_2 == id_rs2) ||
            (div_v_3 && div_rd_3 == id_rs2) || (div_v_4 && div_rd_4 == id_rs2) ||
            (div_v_5 && div_rd_5 == id_rs2) || (div_v_6 && div_rd_6 == id_rs2) ||
            (div_v_7 && div_rd_7 == id_rs2) || (div_v_8 && div_rd_8 == id_rs2)
        )) stall = 1'b1;

        if (id_rd != 0 && (
            (x_is_div && ex_rd == id_rd) ||
            (div_v_1 && div_rd_1 == id_rd) || (div_v_2 && div_rd_2 == id_rd) ||
            (div_v_3 && div_rd_3 == id_rd) || (div_v_4 && div_rd_4 == id_rd) ||
            (div_v_5 && div_rd_5 == id_rd) || (div_v_6 && div_rd_6 == id_rd) ||
            (div_v_7 && div_rd_7 == id_rd) || (div_v_8 && div_rd_8 == id_rd)
        )) stall = 1'b1;

        // 2. Control Hazard (Flush) Resolution
        flush_if_id = x_is_branch_taken;
        flush_id_ex = stall || x_is_branch_taken;
    end
endmodule

/*****************************/
/* 3. MODULE FORWARDING UNIT */
/*****************************/
module Forwarding_Unit (
    input [4:0] ex_rs1,
    input [4:0] ex_rs2,
    input [4:0] mem_rd,
    input mem_reg_write,
    input [4:0] wb_rd,
    input wb_reg_write,
    output reg [1:0] forward_a,
    output reg [1:0] forward_b
);
    
    always @(*) begin
        forward_a = 2'b00;
        if (mem_reg_write && (mem_rd != 0) && (mem_rd == ex_rs1))
            forward_a = 2'b10;
        else if (wb_reg_write && (wb_rd != 0) && (wb_rd == ex_rs1))
            forward_a = 2'b01;

        forward_b = 2'b00;
        if (mem_reg_write && (mem_rd != 0) && (mem_rd == ex_rs2))
            forward_b = 2'b10;
        else if (wb_reg_write && (wb_rd != 0) && (wb_rd == ex_rs2))
            forward_b = 2'b01;
    end
endmodule

/*****************/
/* 4. MODULE ALU */
/*****************/
module ALU (
    input clk,
    input rst,
    input [31:0] pc,
    input [31:0] a,
    input [31:0] b,
    input [6:0] opcode,
    input [2:0] funct3,
    input [6:0] funct7,
    output reg [31:0] result,
    output reg branch_taken,
    output reg [31:0] delayed_div_result
);
    wire is_sub = (opcode == `OPC_REG_REG && funct3 == 3'b000 && funct7 == 7'b0100000) || (opcode == `OPC_BRANCH);
    wire [31:0] cla_b = is_sub ? ~b : b;
    
    
    wire [31:0] cla_sum;
    wire cla_cout;
    
    cla cla_instance (
        .a(a),
        .b(cla_b),
        .cin(is_sub),
        .sum(cla_sum),
        .cout(cla_cout) 
    );
    
    // RV32M Divider Logic
    wire x_is_div = (opcode == `OPC_REG_REG) && (funct7 == 7'd1) && (funct3[2] == 1'b1);
    wire is_dividend_negative = ((funct3 == 3'b100) || (funct3 == 3'b110)) && a[31];
    wire is_divisor_negative  = ((funct3 == 3'b100) || (funct3 == 3'b110)) && b[31];
    wire [31:0] abs_dvd = is_dividend_negative ? (~a + 1) : a;
    wire [31:0] abs_div = is_divisor_negative ? (~b + 1) : b;
    wire [31:0] div_quo, div_rem;

    DividerUnsignedPipelined divider (
        .clk(clk), .rst(rst), .stall(1'b0),
        .i_dividend(abs_dvd), .i_divisor(abs_div),
        .o_quotient(div_quo), .o_remainder(div_rem)
    );

    reg [2:0] div_funct3_pipe [1:8];
    reg div_dvd_neg_pipe [1:8];
    reg div_div_neg_pipe [1:8];
    reg div_by_zero_pipe [1:8];
    reg div_ovf_pipe [1:8];
    reg [31:0] div_a_pipe [1:8];
    integer idx;

    always @(posedge clk) begin
        if (rst) begin
            for(idx=1; idx<=8; idx=idx+1) begin
                div_funct3_pipe[idx] <= 0;
                div_dvd_neg_pipe[idx] <= 0;
                div_div_neg_pipe[idx] <= 0;
                div_by_zero_pipe[idx] <= 0;
                div_ovf_pipe[idx] <= 0;
                div_a_pipe[idx] <= 0;
            end
        end else begin
            div_funct3_pipe[1] <= funct3;
            div_dvd_neg_pipe[1] <= is_dividend_negative;
            div_div_neg_pipe[1] <= is_divisor_negative;
            div_by_zero_pipe[1] <= (b == 0);
            div_ovf_pipe[1]    <= (a == 32'h80000000 && b == 32'hFFFFFFFF);
            div_a_pipe[1]      <= a;
            for(idx=2; idx<=8; idx=idx+1) begin
                div_funct3_pipe[idx] <= div_funct3_pipe[idx-1];
                div_dvd_neg_pipe[idx] <= div_dvd_neg_pipe[idx-1];
                div_div_neg_pipe[idx] <= div_div_neg_pipe[idx-1];
                div_by_zero_pipe[idx] <= div_by_zero_pipe[idx-1];
                div_ovf_pipe[idx]    <= div_ovf_pipe[idx-1];
                div_a_pipe[idx]      <= div_a_pipe[idx-1];
            end
        end
    end

    wire out_quo_neg = ((div_funct3_pipe[8] == 3'b100) || (div_funct3_pipe[8] == 3'b110)) & (div_dvd_neg_pipe[8] ^ div_div_neg_pipe[8]);
    wire out_rem_neg = ((div_funct3_pipe[8] == 3'b100) || (div_funct3_pipe[8] == 3'b110)) & div_dvd_neg_pipe[8];
    wire [31:0] out_final_quo = out_quo_neg ? (~div_quo + 1) : div_quo;
    wire [31:0] out_final_rem = out_rem_neg ? (~div_rem + 1) : div_rem;

    always @(*) begin
        delayed_div_result = 0;
        case (div_funct3_pipe[8])
            3'b100: delayed_div_result = div_by_zero_pipe[8] ? 32'hFFFFFFFF : div_ovf_pipe[8] ? 32'h80000000 : out_final_quo; 
            3'b101: delayed_div_result = div_by_zero_pipe[8] ? 32'hFFFFFFFF : div_quo; 
            3'b110: delayed_div_result = div_by_zero_pipe[8] ? div_a_pipe[8] : div_ovf_pipe[8] ? 32'h00000000 : out_final_rem; 
            3'b111: delayed_div_result = div_by_zero_pipe[8] ? div_a_pipe[8] : div_rem; 
        endcase
    end

    reg [63:0] mul_res;
    always @(*) begin
        result = 32'd0;
        mul_res = 64'd0;

        if (opcode == `OPC_LUI) result = b; // b is immediate
        else if (opcode == `OPC_JAL || opcode == `OPC_JALR) result = pc + 4;
        else if (x_is_div) begin
             result = 0;
        end else if (opcode == `OPC_REG_REG && funct7 == 7'd1) begin
             case (funct3)
                 3'b000: result = a * b; 
                 3'b001: begin mul_res = $signed(a) * $signed(b); result = mul_res[63:32]; end 
                 3'b010: begin mul_res = $signed(a) * $signed({1'b0, b}); result = mul_res[63:32]; end 
                 3'b011: begin mul_res = {1'b0, a} * {1'b0, b}; result = mul_res[63:32]; end 
                 default: result = 0;
             endcase
        end else if (opcode == `OPC_LOAD || opcode == `OPC_STORE || opcode == `OPC_AUIPC) begin
             result = cla_sum; // Sử dụng cla_sum từ module cla
        end else begin
            case (funct3)
                3'b000: result = cla_sum; // Sử dụng cla_sum từ module cla
                3'b001: result = a << b[4:0]; 
                3'b010: result = ($signed(a) < $signed(b)) ? 1 : 0; 
                3'b011: result = (a < b) ? 1 : 0; 
                3'b100: result = a ^ b; 
                3'b101: begin
                    if (funct7[5]) result = $signed(a) >>> b[4:0];
                    else result = a >> b[4:0];
                end
                3'b110: result = a | b; 
                3'b111: result = a & b; 
            endcase
        end
    end

    always @(*) begin
        case (funct3)
            3'b000: branch_taken = (a == b); 
            3'b001: branch_taken = (a != b); 
            3'b100: branch_taken = ($signed(a) < $signed(b)); 
            3'b101: branch_taken = ($signed(a) >= $signed(b)); 
            3'b110: branch_taken = (a < b); 
            3'b111: branch_taken = (a >= b); 
            default: branch_taken = 0;
        endcase
    end
endmodule

/***************************/
/* 5. MAIN DATAPATH MODULE */
/***************************/
module DatapathPipelined (
    input clk,
    input rst,
    output [`REG_SIZE:0] pc_to_imem,
    input  [`INST_SIZE:0] inst_from_imem,
    output reg [`REG_SIZE:0] addr_to_dmem,
    input  [`REG_SIZE:0] load_data_from_dmem,
    output reg [`REG_SIZE:0] store_data_to_dmem,
    output reg [3:0] store_we_to_dmem,
    output reg halt,
    output reg [`REG_SIZE:0] trace_writeback_pc,
    output reg [`INST_SIZE:0] trace_writeback_inst
);

    // Hazard & Stall Wires
    wire stall;
    wire flush_id_ex, flush_if_id;
    
    // FETCH STAGE Wires
    reg  [`REG_SIZE:0] f_pc;
    wire [`REG_SIZE:0] f_next_pc;
    wire x_is_branch_taken;
    wire [`REG_SIZE:0] x_target_pc;
    
    reg [`REG_SIZE-1:0] cycles_current;
    always @(posedge clk) begin
        if (rst) cycles_current <= 0;
        else cycles_current <= cycles_current + 1;
    end
    
    /*******************/
    /* FETCH STAGE (F) */
    /*******************/
    assign f_next_pc = (x_is_branch_taken) ? x_target_pc : f_pc + 4;
    assign pc_to_imem = f_pc;

    always @(posedge clk) begin
        if (rst) f_pc <= 0;
        else if (!stall) f_pc <= f_next_pc;
    end

    /******************/
    /* IF/ID REGISTER */
    /******************/
    reg [`REG_SIZE:0] d_pc;
    reg [`INST_SIZE:0] d_inst;

    always @(posedge clk) begin
        if (rst || flush_if_id) begin
            d_pc <= 0;
            d_inst <= 32'h00000013; // NOP
        end else if (!stall) begin
            d_pc <= f_pc;
            d_inst <= inst_from_imem;
        end
    end

    /********************/
    /* DECODE STAGE (D) */
    /********************/
    wire [6:0] d_opcode, d_funct7;
    wire [2:0] d_funct3;
    wire [4:0] d_rs1, d_rs2, d_rd;
    wire [31:0] d_imm;
    wire d_reg_write, d_mem_read, d_mem_write, d_branch, d_jump, d_halt;

    Decode_Unit du (
        .inst(d_inst), .opcode(d_opcode), .funct3(d_funct3), .funct7(d_funct7),
        .rs1(d_rs1), .rs2(d_rs2), .rd(d_rd), .imm(d_imm),
        .ctrl_reg_write(d_reg_write), .ctrl_mem_read(d_mem_read),
        .ctrl_mem_write(d_mem_write), .ctrl_branch(d_branch),
        .ctrl_jump(d_jump), .ctrl_halt(d_halt)
    );

    wire [31:0] w_write_data;
    reg w_reg_write;
    reg [4:0] w_rd;
    wire [31:0] d_rs1_data, d_rs2_data;

    wire [31:0] delayed_div_result;

    reg [4:0] div_rd_pipe [1:8];
    reg       div_valid_pipe [1:8];
    integer pipe_idx;
    wire x_is_div;
    reg [4:0] x_rd;

    always @(posedge clk) begin
        if (rst) begin
            for(pipe_idx=1; pipe_idx<=8; pipe_idx=pipe_idx+1) begin
                div_rd_pipe[pipe_idx] <= 0;
                div_valid_pipe[pipe_idx] <= 0;
            end
        end else begin
            div_valid_pipe[1] <= x_is_div;
            div_rd_pipe[1]    <= x_rd;
            for(pipe_idx=2; pipe_idx<=8; pipe_idx=pipe_idx+1) begin
                div_valid_pipe[pipe_idx] <= div_valid_pipe[pipe_idx-1];
                div_rd_pipe[pipe_idx]    <= div_rd_pipe[pipe_idx-1];
            end
        end
    end

    RegFile rf (
        .clk(clk), .rst(rst),
        .we(w_reg_write), .rd(w_rd), .rd_data(w_write_data),
        .we_div(div_valid_pipe[8]), .rd_div(div_rd_pipe[8]), .rd_data_div(delayed_div_result),
        .rs1(d_rs1), .rs1_data(d_rs1_data),
        .rs2(d_rs2), .rs2_data(d_rs2_data)
    );

    reg x_mem_read;
    
    
    // Hazard Detection Instantiation
    Hazard_Detection hd (
        .id_rs1(d_rs1), 
        .id_rs2(d_rs2), 
        .id_rd(d_rd),
        .x_is_div(x_is_div),
        .ex_mem_read(x_mem_read), 
        .ex_rd(x_rd), 
        .x_is_branch_taken(x_is_branch_taken),
        .div_rd_1(div_rd_pipe[1]), .div_rd_2(div_rd_pipe[2]), .div_rd_3(div_rd_pipe[3]), .div_rd_4(div_rd_pipe[4]),
        .div_rd_5(div_rd_pipe[5]), .div_rd_6(div_rd_pipe[6]), .div_rd_7(div_rd_pipe[7]), .div_rd_8(div_rd_pipe[8]),
        .div_v_1(div_valid_pipe[1]), .div_v_2(div_valid_pipe[2]), .div_v_3(div_valid_pipe[3]), .div_v_4(div_valid_pipe[4]),
        .div_v_5(div_valid_pipe[5]), .div_v_6(div_valid_pipe[6]), .div_v_7(div_valid_pipe[7]), .div_v_8(div_valid_pipe[8]),
        .stall(stall),
        .flush_if_id(flush_if_id),
        .flush_id_ex(flush_id_ex)
    );

    /******************/
    /* ID/EX REGISTER */
    /******************/
    reg [31:0] x_pc, x_rs1_data, x_rs2_data, x_imm;
    reg [4:0]  x_rs1, x_rs2;
    reg [6:0]  x_opcode, x_funct7;
    reg [2:0]  x_funct3;
    reg x_reg_write, x_mem_write, x_branch, x_jump, x_halt;
    
    assign x_is_div = (x_opcode == `OPC_REG_REG) && (x_funct7 == 7'd1) && (x_funct3[2] == 1'b1);

    always @(posedge clk) begin
        if (rst || flush_id_ex) begin
            x_pc <= 0; x_rs1_data <= 0; x_rs2_data <= 0; x_imm <= 0;
            x_rs1 <= 0; x_rs2 <= 0; x_rd <= 0; x_opcode <= 0; x_funct3 <= 0; x_funct7 <= 0;
            x_reg_write <= 0; x_mem_read <= 0; x_mem_write <= 0; x_branch <= 0; x_jump <= 0; x_halt <= 0;
        end else begin
            x_pc <= d_pc; x_rs1_data <= d_rs1_data; x_rs2_data <= d_rs2_data; x_imm <= d_imm;
            x_rs1 <= d_rs1; x_rs2 <= d_rs2; x_rd <= d_rd;
            x_opcode <= d_opcode; x_funct3 <= d_funct3; x_funct7 <= d_funct7;
            x_reg_write <= d_reg_write; x_mem_read <= d_mem_read; x_mem_write <= d_mem_write;
            x_branch <= d_branch; x_jump <= d_jump; x_halt <= d_halt;
        end
    end

    /*********************/
    /* EXECUTE STAGE (X) */
    /*********************/
    wire [1:0] forward_a, forward_b;
    
    reg m_reg_write;
    reg [4:0] m_rd;
    reg [31:0] m_alu_res;

    Forwarding_Unit fw (
        .ex_rs1(x_rs1), .ex_rs2(x_rs2),
        .mem_rd(m_rd), .mem_reg_write(m_reg_write),
        .wb_rd(w_rd), .wb_reg_write(w_reg_write),
        .forward_a(forward_a), .forward_b(forward_b)
    );

    wire [31:0] fw_a_data = (forward_a == 2'b10) ? m_alu_res : (forward_a == 2'b01) ? w_write_data : x_rs1_data;
    wire [31:0] fw_b_data = (forward_b == 2'b10) ? m_alu_res : (forward_b == 2'b01) ? w_write_data : x_rs2_data;

    wire [31:0] alu_in_a = (x_opcode == `OPC_AUIPC) ? x_pc : fw_a_data;
    wire [31:0] alu_in_b = (x_opcode == `OPC_REG_REG || x_opcode == `OPC_BRANCH) ? fw_b_data : x_imm;

    wire alu_branch_taken;
    wire [31:0] x_alu_res;

    ALU alu_unit (
        .clk(clk), .rst(rst), .pc(x_pc), .a(alu_in_a), .b(alu_in_b),
        .opcode(x_opcode), .funct3(x_funct3), .funct7(x_funct7),
        .result(x_alu_res), .branch_taken(alu_branch_taken), .delayed_div_result(delayed_div_result)
    );

    assign x_is_branch_taken = (x_branch && alu_branch_taken) || x_jump;
    assign x_target_pc = (x_opcode == `OPC_JALR) ? (fw_a_data + x_imm) & ~32'd1 : (x_pc + x_imm);

    /******************/
    /* EX/MEM REGISTER */
    /******************/
    reg [31:0] m_pc, m_rs2_data;
    reg [6:0] m_opcode;
    reg [2:0] m_funct3;
    reg m_mem_read, m_mem_write, m_halt;

    always @(posedge clk) begin
        if (rst) begin
            m_pc <= 0; m_alu_res <= 0; m_rs2_data <= 0; m_rd <= 0;
            m_opcode <= 0; m_funct3 <= 0;
            m_reg_write <= 0; m_mem_read <= 0; m_mem_write <= 0; m_halt <= 0;
        end else begin
            m_pc <= x_pc; m_alu_res <= x_alu_res; m_rs2_data <= fw_b_data; m_rd <= x_rd;
            m_opcode <= x_opcode; m_funct3 <= x_funct3;
            m_reg_write <= x_reg_write && !x_is_div;
            m_mem_read <= x_mem_read; m_mem_write <= x_mem_write; m_halt <= x_halt;
        end
    end

    /********************/
    /* MEMORY STAGE (M) */
    /********************/
    always @(*) begin
        addr_to_dmem = m_alu_res;
        store_data_to_dmem = 0;
        store_we_to_dmem = 0;

        if (m_mem_write) begin
            case (m_funct3) 
                3'b000: begin // sb
                    case (m_alu_res[1:0])
                        2'b00: begin store_we_to_dmem = 4'b0001; store_data_to_dmem[7:0]   = m_rs2_data[7:0]; end 
                        2'b01: begin store_we_to_dmem = 4'b0010; store_data_to_dmem[15:8]  = m_rs2_data[7:0]; end 
                        2'b10: begin store_we_to_dmem = 4'b0100; store_data_to_dmem[23:16] = m_rs2_data[7:0]; end 
                        2'b11: begin store_we_to_dmem = 4'b1000; store_data_to_dmem[31:24] = m_rs2_data[7:0]; end 
                    endcase
                end
                3'b001: begin // sh
                    case (m_alu_res[1])
                        1'b0: begin store_we_to_dmem = 4'b0011; store_data_to_dmem[15:0]  = m_rs2_data[15:0]; end 
                        1'b1: begin store_we_to_dmem = 4'b1100; store_data_to_dmem[31:16] = m_rs2_data[15:0]; end 
                    endcase
                end
                3'b010: begin // sw
                    store_we_to_dmem = 4'b1111; 
                    store_data_to_dmem = m_rs2_data; 
                end
            endcase
        end
    end

    reg [31:0] loaded_val_aligned;
    always @(*) begin
        loaded_val_aligned = load_data_from_dmem; 
        if (m_mem_read) begin
            case (m_funct3)
                3'b000: case(m_alu_res[1:0]) // lb
                    2'b00: loaded_val_aligned = {{24{load_data_from_dmem[7]}}, load_data_from_dmem[7:0]};
                    2'b01: loaded_val_aligned = {{24{load_data_from_dmem[15]}}, load_data_from_dmem[15:8]};
                    2'b10: loaded_val_aligned = {{24{load_data_from_dmem[23]}}, load_data_from_dmem[23:16]};
                    2'b11: loaded_val_aligned = {{24{load_data_from_dmem[31]}}, load_data_from_dmem[31:24]};
                endcase
                3'b001: case(m_alu_res[1]) // lh
                    1'b0: loaded_val_aligned = {{16{load_data_from_dmem[15]}}, load_data_from_dmem[15:0]};
                    1'b1: loaded_val_aligned = {{16{load_data_from_dmem[31]}}, load_data_from_dmem[31:16]};
                endcase
                3'b100: case(m_alu_res[1:0]) // lbu
                    2'b00: loaded_val_aligned = {24'b0, load_data_from_dmem[7:0]};
                    2'b01: loaded_val_aligned = {24'b0, load_data_from_dmem[15:8]};
                    2'b10: loaded_val_aligned = {24'b0, load_data_from_dmem[23:16]};
                    2'b11: loaded_val_aligned = {24'b0, load_data_from_dmem[31:24]};
                endcase
                3'b101: case(m_alu_res[1]) // lhu
                    1'b0: loaded_val_aligned = {16'b0, load_data_from_dmem[15:0]};
                    1'b1: loaded_val_aligned = {16'b0, load_data_from_dmem[31:16]};
                endcase
                default: loaded_val_aligned = load_data_from_dmem; // lw
            endcase
        end
    end

    /******************/
    /* MEM/WB REGISTER */
    /******************/
    reg [31:0] w_pc, w_alu_res, w_mem_read_data;
    reg [6:0] w_opcode;
    reg w_halt;

    always @(posedge clk) begin
        if (rst) begin
            w_pc <= 0; w_alu_res <= 0; w_mem_read_data <= 0;
            w_opcode <= 0; w_rd <= 0; w_reg_write <= 0; w_halt <= 0;
        end else begin
            w_pc <= m_pc; w_alu_res <= m_alu_res; w_mem_read_data <= loaded_val_aligned;
            w_opcode <= m_opcode; w_rd <= m_rd; w_reg_write <= m_reg_write; w_halt <= m_halt;
        end
    end

    /***********************/
    /* WRITEBACK STAGE (W) */
    /***********************/
    assign w_write_data = (w_opcode == `OPC_LOAD) ? w_mem_read_data : w_alu_res;

    reg halt_pending;
    always @(posedge clk) begin
        if (rst) halt_pending <= 1'b0;
        else if (w_halt) halt_pending <= 1'b1;
    end

    always @(*) begin
        trace_writeback_pc   = w_pc;
        trace_writeback_inst = 0;
        halt                 = (w_halt || halt_pending) && !(x_is_div || div_valid_pipe[1] || div_valid_pipe[2] || div_valid_pipe[3] || div_valid_pipe[4] || div_valid_pipe[5] || div_valid_pipe[6] || div_valid_pipe[7] || div_valid_pipe[8]);
    end

endmodule

/***************************/
/* 6. REGISTER FILE MODULE */
/***************************/
module RegFile (
  input      [        4:0] rd,
  input      [`REG_SIZE:0] rd_data,
  input      [        4:0] rs1,
  output reg [`REG_SIZE:0] rs1_data,
  input      [        4:0] rs2,
  output reg [`REG_SIZE:0] rs2_data,
  input      [        4:0] rd_div,
  input      [`REG_SIZE:0] rd_data_div,
  input                    clk,
  input                    we,
  input                    we_div,
  input                    rst
);
  localparam NumRegs = 32;
  reg [`REG_SIZE:0] regs[0:NumRegs-1];
  integer i;

  // TODO: your code here

  // read
  always @(*) begin
    if(rs1 == 0) begin
      rs1_data = 0; //x0
    end
    else if (we && (rs1 == rd)) begin
      rs1_data = rd_data;
    end
    else if (we_div && (rs1 == rd_div)) begin
      rs1_data = rd_data_div;
    end
    else begin
      rs1_data = regs[rs1];
    end

    if(rs2 == 0) begin
      rs2_data = 0; //x0
    end
    else if (we && (rs2 == rd)) begin
      rs2_data = rd_data;
    end
    else if (we_div && (rs2 == rd_div)) begin
      rs2_data = rd_data_div;
    end
    else begin
      rs2_data = regs[rs2];
    end
  end

  //write
  always @(posedge clk) begin
    if(rst) begin
      for(i = 0; i < NumRegs; i = i + 1) begin
        regs[i] <= 0;
      end
    end
    else begin
        if (we && rd != 0) regs[rd] <= rd_data;
        if (we_div && rd_div != 0) regs[rd_div] <= rd_data_div;
    end
  end

endmodule

/*********************************/
/* 7. MEMORY SINGLE CYCLE MODULE */
/*********************************/
module MemorySingleCycle #(
    parameter NUM_WORDS = 512
) (
    input                    rst,                // rst for both imem and dmem
    input                    clk,                // clock for both imem and dmem
                                                 // The memory reads/writes on @(negedge clk)
    input      [`REG_SIZE:0] pc_to_imem,          // must always be aligned to a 4B boundary
    output reg [`REG_SIZE:0] inst_from_imem,      // the value at memory location pc_to_imem
    input      [`REG_SIZE:0] addr_to_dmem,        // must always be aligned to a 4B boundary
    output reg [`REG_SIZE:0] load_data_from_dmem, // the value at memory location addr_to_dmem
    input      [`REG_SIZE:0] store_data_to_dmem,  // the value to be written to addr_to_dmem, controlled by store_we_to_dmem
    // Each bit determines whether to write the corresponding byte of store_data_to_dmem to memory location addr_to_dmem.
    // E.g., 4'b1111 will write 4 bytes. 4'b0001 will write only the least-significant byte.
    input      [        3:0] store_we_to_dmem
);

  // memory is arranged as an array of 4B words
  reg [`REG_SIZE:0] mem_array[0:NUM_WORDS-1];

  // preload instructions to mem_array
  initial begin
    $readmemh("mem_initial_contents.hex", mem_array);
  end

  localparam AddrMsb = $clog2(NUM_WORDS) + 1;
  localparam AddrLsb = 2;

  always @(negedge clk) begin
    inst_from_imem <= mem_array[pc_to_imem[AddrMsb:AddrLsb]];
  end

  always @(negedge clk) begin
    if (store_we_to_dmem[0]) begin
      mem_array[addr_to_dmem[AddrMsb:AddrLsb]][7:0] <= store_data_to_dmem[7:0];
    end
    if (store_we_to_dmem[1]) begin
      mem_array[addr_to_dmem[AddrMsb:AddrLsb]][15:8] <= store_data_to_dmem[15:8];
    end
    if (store_we_to_dmem[2]) begin
      mem_array[addr_to_dmem[AddrMsb:AddrLsb]][23:16] <= store_data_to_dmem[23:16];
    end
    if (store_we_to_dmem[3]) begin
      mem_array[addr_to_dmem[AddrMsb:AddrLsb]][31:24] <= store_data_to_dmem[31:24];
    end
    // dmem is "read-first": read returns value before the write
    load_data_from_dmem <= mem_array[addr_to_dmem[AddrMsb:AddrLsb]];
  end
endmodule

/***********************/
/* 8. PROCESSOR MODULE */
/***********************/
/* This design has just one clock for both processor and memory. */
module Processor (
    input                 clk,
    input                 rst,
    output                halt,
    output [ `REG_SIZE:0] trace_writeback_pc,
    output [`INST_SIZE:0] trace_writeback_inst
);

  wire [`INST_SIZE:0] inst_from_imem;
  wire [ `REG_SIZE:0] pc_to_imem, mem_data_addr, mem_data_loaded_value, mem_data_to_write;
  wire [         3:0] mem_data_we;

  // This wire is set by cocotb to the name of the currently-running test, to make it easier
  // to see what is going on in the waveforms.
  wire [(8*32)-1:0] test_case;

  MemorySingleCycle #(
      .NUM_WORDS(8192)
  ) memory (
    .rst                 (rst),
    .clk                 (clk),
    // imem is read-only
    .pc_to_imem          (pc_to_imem),
    .inst_from_imem      (inst_from_imem),
    // dmem is read-write
    .addr_to_dmem        (mem_data_addr),
    .load_data_from_dmem (mem_data_loaded_value),
    .store_data_to_dmem  (mem_data_to_write),
    .store_we_to_dmem    (mem_data_we)
  );

  DatapathPipelined datapath (
    .clk                  (clk),
    .rst                  (rst),
    .pc_to_imem           (pc_to_imem),
    .inst_from_imem       (inst_from_imem),
    .addr_to_dmem         (mem_data_addr),
    .store_data_to_dmem   (mem_data_to_write),
    .store_we_to_dmem     (mem_data_we),
    .load_data_from_dmem  (mem_data_loaded_value),
    .halt                 (halt),
    .trace_writeback_pc   (trace_writeback_pc),
    .trace_writeback_inst (trace_writeback_inst)
  );

endmodule
