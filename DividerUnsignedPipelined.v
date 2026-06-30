module DividerUnsignedPipelined (
    input             clk, rst, stall,
    input      [31:0] i_dividend,
    input      [31:0] i_divisor,
    output reg [31:0] o_remainder,
    output reg [31:0] o_quotient
);

    // Pipeline registers for 8 stages (0 to 7)
    reg [31:0] pipe_rem [0:7];
    reg [31:0] pipe_quo [0:7];
    reg [31:0] pipe_div [0:7];
    reg [31:0] pipe_dvd [0:7];

    genvar i, j;
    generate
        for (i = 0; i < 8; i = i + 1) begin : pipe_stages
            
            // 1. Prepare Stage Inputs
            wire [31:0] stage_dvd_in;
            wire [31:0] stage_div_in;
            wire [31:0] stage_rem_in;
            wire [31:0] stage_quo_in;

            if (i == 0) begin
                assign stage_dvd_in = i_dividend;
                assign stage_div_in = i_divisor;
                assign stage_rem_in = 32'b0;
                assign stage_quo_in = 32'b0;
            end else begin
                assign stage_dvd_in = pipe_dvd[i-1];
                assign stage_div_in = pipe_div[i-1];
                assign stage_rem_in = pipe_rem[i-1];
                assign stage_quo_in = pipe_quo[i-1];
            end

            // 2. Combinational Logic (4 Iterations)
            wire [31:0] temp_dvd [0:4];
            wire [31:0] temp_rem [0:4];
            wire [31:0] temp_quo [0:4];

            assign temp_dvd[0] = stage_dvd_in;
            assign temp_rem[0] = stage_rem_in;
            assign temp_quo[0] = stage_quo_in;

            for (j = 0; j < 4; j = j + 1) begin : loop_iters
                divu_1iter_lab4 u_iter (
                    .i_dividend (temp_dvd[j]),
                    .i_divisor  (stage_div_in),
                    .i_remainder(temp_rem[j]),
                    .i_quotient (temp_quo[j]),
                    .o_dividend (temp_dvd[j+1]),
                    .o_remainder(temp_rem[j+1]),
                    .o_quotient (temp_quo[j+1])
                );
            end

            // 3. Sequential Logic (Pipeline Update)
            always @(posedge clk) begin
                if (rst) begin
                    // [FIX] Reset EVERYTHING. No "if (i < 7)" here.
                    pipe_rem[i] <= 0;
                    pipe_quo[i] <= 0;
                    pipe_div[i] <= 0;
                    pipe_dvd[i] <= 0;
                    
                    // Reset outputs only on the last stage
                    if (i == 7) begin
                        o_remainder <= 0;
                        o_quotient  <= 0;
                    end
                end 
                else if (!stall) begin
                    if (i < 7) begin
                        pipe_rem[i] <= temp_rem[4];
                        pipe_quo[i] <= temp_quo[4];
                        pipe_div[i] <= stage_div_in;
                        pipe_dvd[i] <= temp_dvd[4];
                    end else begin
                        // Last stage writes to output ports
                        o_remainder <= temp_rem[4];
                        o_quotient  <= temp_quo[4];
                        // Optional: Write to internal regs too to avoid "unused" warnings
                        pipe_rem[i] <= temp_rem[4];
                        pipe_quo[i] <= temp_quo[4];
                        pipe_div[i] <= stage_div_in;
                        pipe_dvd[i] <= temp_dvd[4];
                    end
                end
            end
        end
    endgenerate

endmodule

// Include the 1-iter module (Keep this as you had it)
module divu_1iter_lab4 (
    input  [31:0] i_dividend,
    input  [31:0] i_divisor,
    input  [31:0] i_remainder,
    input  [31:0] i_quotient,
    output [31:0] o_dividend,
    output [31:0] o_remainder,
    output [31:0] o_quotient
);
    wire bit_in = i_dividend[31];
    wire [32:0] temp = ({1'b0, i_remainder} << 1) | {32'b0, bit_in};
    wire [32:0] divisor_ext = {1'b0, i_divisor};
    
    wire sub = (temp >= divisor_ext) ? 1'b1 : 1'b0;
    wire [32:0] remainder_next = sub ? (temp - divisor_ext) : temp;

    assign o_remainder = remainder_next[31:0];
    assign o_quotient  = {i_quotient[30:0], sub};
    assign o_dividend  = {i_dividend[30:0], 1'b0};
endmodule