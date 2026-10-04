`timescale 1ns/1ps
module reset_tb;
 reg clk=0,ext_resetn=0,aux_resetn=1;
 wire [0:0] peripheral_resetn;
 always #20 clk=~clk;
 ibex_ps_reset_sync_0 dut(
   .slowest_sync_clk(clk),.ext_reset_in(ext_resetn),
   .aux_reset_in(aux_resetn),.mb_debug_sys_rst(1'b0),.dcm_locked(1'b1),
   .mb_reset(),.bus_struct_reset(),.peripheral_reset(),
   .interconnect_aresetn(),.peripheral_aresetn(peripheral_resetn)
 );
 initial begin
   repeat(4) @(negedge clk);
   ext_resetn=1;
   repeat(200) @(negedge clk);
   if(peripheral_resetn!==1'b1) $fatal(1,"Reset did not release with auxiliary high");
   aux_resetn=0; // Reproduce the first bitstream's wiring error.
   repeat(200) @(negedge clk);
   if(peripheral_resetn!==1'b0) $fatal(1,"Auxiliary low should hold reset");
   aux_resetn=1;
   repeat(200) @(negedge clk);
   if(peripheral_resetn!==1'b1) $fatal(1,"Reset did not recover");
   $display("PASS: real Xilinx reset IP releases at aux=1; aux=0 reproduces permanent reset");
   $finish;
 end
 initial begin #40000; $fatal(1,"Reset simulation timeout"); end
endmodule
