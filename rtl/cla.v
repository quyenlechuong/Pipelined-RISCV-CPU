// ---------- gp1: generate/propagate 1-bit ----------
module gp1(
  input  wire a,
  input  wire b,
  output wire g,
  output wire p
);
  assign g = a & b;
  assign p = a | b;
endmodule

// ---------- gp4: group 4-bit block ----------
module gp4(
  input  wire [3:0] g,
  input  wire [3:0] p,
  input  wire       c0,
  output wire [2:0] c,   // c[0]=c1, c[1]=c2, c[2]=c3
  output wire       G,
  output wire       P
);
  assign P = &p;

  
  wire c1 = g[0] | (p[0] & c0);
  wire c2 = g[1] | (p[1] & c1);
  wire c3 = g[2] | (p[2] & c2);
  assign c = {c3, c2, c1};

  // G_group
  assign G = g[3]
           | (p[3] & g[2])
           | (p[3] & p[2] & g[1])
           | (p[3] & p[2] & p[1] & g[0]);
endmodule

// ---------- gp8: top level combine of 8 gp4 ----------
module gp8(
  input  wire [7:0] G4,
  input  wire [7:0] P4,
  input  wire       c0,
  output wire [6:0] cout_gp8,  // {c28,c24,c20,c16,c12,c8,c4}
  output wire       cout
);
  wire c4  = G4[0] | (P4[0] & c0);
  wire c8  = G4[1] | (P4[1] & c4);
  wire c12 = G4[2] | (P4[2] & c8);
  wire c16 = G4[3] | (P4[3] & c12);
  wire c20 = G4[4] | (P4[4] & c16);
  wire c24 = G4[5] | (P4[5] & c20);
  wire c28 = G4[6] | (P4[6] & c24);
  wire c32 = G4[7] | (P4[7] & c28);

  assign cout_gp8 = {c28, c24, c20, c16, c12, c8, c4};
  assign cout = c32;
endmodule

// ---------- cla: 32-bit adder ----------
module cla(
  input  wire [31:0] a,
  input  wire [31:0] b,
  input  wire        cin,
  output wire [31:0] sum,
  output wire        cout
);
  // Bit-level G/P
  wire [31:0] g_vector, p_vector;
  genvar i;
  generate
    for (i = 0; i < 32; i = i + 1) begin : GP1S
      gp1 u_gp1(.a(a[i]), .b(b[i]), .g(g_vector[i]), .p(p_vector[i]));
    end
  endgenerate

  // gp4
  wire [7:0] G4, P4;
  wire [2:0] c_internal [7:0];
  wire [7:0] cin_gp4;
  assign cin_gp4[0] = cin;

  // gp8 top-level
  wire [6:0] cout_gp8;
  gp8 u_top (
    .G4       (G4),
    .P4       (P4),
    .c0       (cin),
    .cout_gp8 (cout_gp8),
    .cout     (cout)
  );

  assign cin_gp4[1] = cout_gp8[0];
  assign cin_gp4[2] = cout_gp8[1];
  assign cin_gp4[3] = cout_gp8[2];
  assign cin_gp4[4] = cout_gp8[3];
  assign cin_gp4[5] = cout_gp8[4];
  assign cin_gp4[6] = cout_gp8[5];
  assign cin_gp4[7] = cout_gp8[6];

  genvar x;
  generate
    for (x = 0; x < 8; x = x + 1) begin : GP4S
      gp4 u_gp4 (
        .g  (g_vector[4*x+3 : 4*x]),
        .p  (p_vector[4*x+3 : 4*x]),
        .c0 (cin_gp4[x]),
        .c  (c_internal[x]),
        .G  (G4[x]),
        .P  (P4[x])
      );
    end
  endgenerate

  wire [31:0] c_vector;

  genvar z;
  generate
    for (z = 0; z < 8; z = z + 1) begin : CIN_BITS
      assign c_vector[4*z+0] = cin_gp4[z];
      assign c_vector[4*z+1] = c_internal[z][0];
      assign c_vector[4*z+2] = c_internal[z][1];
      assign c_vector[4*z+3] = c_internal[z][2];
    end
  endgenerate

  // Sum
  assign sum = (a ^ b) ^ c_vector;
endmodule