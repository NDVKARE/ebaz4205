`timescale 1ns/1ps
// One address per physical port; four byte lanes provide write strobes.
module ibex_shared_ram (
 input wire clk, cpu_en, cpu_we, ps_en, ps_we,
 input wire [3:0] cpu_be, ps_be,
 input wire [9:0] cpu_addr, ps_addr,
 input wire [31:0] cpu_wdata, ps_wdata,
 output wire [31:0] cpu_rdata, ps_rdata
);
 genvar lane;
 generate for(lane=0;lane<4;lane=lane+1) begin: bytes
   (* ram_style="block" *) reg [7:0] mem[0:1023];
   reg [7:0] cpu_q,ps_q;
   assign cpu_rdata[lane*8+:8]=cpu_q;
   assign ps_rdata[lane*8+:8]=ps_q;
   always @(posedge clk) if(cpu_en) begin
     cpu_q<=mem[cpu_addr];
     if(cpu_we && cpu_be[lane]) mem[cpu_addr]<=cpu_wdata[lane*8+:8];
   end
   always @(posedge clk) if(ps_en) begin
     ps_q<=mem[ps_addr];
     if(ps_we && ps_be[lane]) mem[ps_addr]<=ps_wdata[lane*8+:8];
   end
 end endgenerate
endmodule
