/*
  zoo module
*/
package mypkg;

`resetall
`undefineall
`include "isa.vh"
`undef D
`define D(x, y) initial $display("start", x, y)
`define DELAY #1
`define WIDTH 32


module add_sub (x, y, z, sign);

  parameter WIDTH = 8;
  parameter W2 = 8 * WIDTH;

  input [WIDTH-1:0] x, y;
  output carry;
  output [WIDTH-1:0] z;
  input sign;

wire [WIDTH-1:0] add, sub;

// logic
`ifdef E0
  assign add = x + y;
`elsif E1
  assign add = x + y;
`else
  assign add = x + y;
`endif

assign sub = x - y;
assign z = sign ? sub : add;

`D(5, 7);

endmodule: add_sub

module bar (
  input a, // `line define in the port list
`line 123 "foo.v" 0
  output b
);
endmodule

module alu (
  input [31:0] a,
  input [31:0] b,
  output [31:0] res,
  input clk
);

wire [31:0] tmp;

add_sub #(32) u0 (
  .x(a),
  .y(b),
`ifdef CARRY
  .carry(carry),
`endif
  .z(tmp),
  .sign(1'b0)
);

add_sub #(32) u0 (
  a, b, ,  // missing argument
  tmp[PARAM-1:0], // expressions with parameters
  1'b0
);

assign res = tmp;

endmodule

module foo #(
  parameter P1 = 32,
  parameter P2 = (P1 / 8), // parrents
  parameter P3 = P1 ? P2 : 64 // trinary
)();

module mod ();
  always_comb foo = bar.baz[7:0];
endmodule

always @ (posedge clk) begin
  a.b <= b;
  a.b(c);
  {x0, x1, x2} <= y; // deconcat
  x <= `DELAY y; // define delay
end

assign x = -(8 * W);
assign x[P1-1:0] = y; // vector slice assignment
assign x = `WIDTH'b0; // define as vector size
assign x = $random(seed); // system functions
assign x = mypkg::add(1, 3);

endmodule

module mod ();
always_comb foo = bar.baz[7:0];
endmodule
