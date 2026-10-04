// Functional model for Verilator only. Vivado synthesis uses its BUFGCE primitive.
module BUFGCE(input wire I, CE, output wire O);
 reg enabled=0;
 always @(negedge I) enabled<=CE;
 assign O=I && enabled;
endmodule
