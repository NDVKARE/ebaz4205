`timescale 1ns/1ps
module ibex_soc #(parameter LED_HALF_PERIOD = 12500000) (
 input wire clk, resetn,
 input wire [31:0] s_axi_awaddr, input wire s_axi_awvalid, output wire s_axi_awready,
 input wire [31:0] s_axi_wdata, input wire [3:0] s_axi_wstrb,
 input wire s_axi_wvalid, output wire s_axi_wready,
 output reg [1:0] s_axi_bresp, output reg s_axi_bvalid, input wire s_axi_bready,
 input wire [31:0] s_axi_araddr, input wire s_axi_arvalid, output wire s_axi_arready,
 output wire [31:0] s_axi_rdata, output reg [1:0] s_axi_rresp,
 output reg s_axi_rvalid, input wire s_axi_rready,
 output wire led6_green_n, led6_red_n, output wire [3:0] data_gpio, output wire cpu_fault
);
 reg [1:0] rst_sync=0;
 always @(posedge clk or negedge resetn)
   if(!resetn) rst_sync<=0; else rst_sync<={rst_sync[0],1'b1};
 wire rstn=rst_sync[1];
 wire ireq,dreq,dwe;
 wire [3:0] dbe;
 wire [31:0] ia,da,dw;
 reg [31:0] ir,dr;
 reg iv,dv,ie,de;
 (* ram_style="block" *) reg [31:0] rom[0:4095];
 (* ram_style="block" *) reg [31:0] ram[0:2047];
 initial $readmemh("firmware.hex",rom);
 reg [31:0] rom_data,ram_data,axi_reg_data;
 wire [31:0] shared_cpu_data,shared_axi_data;
 reg [2:0] data_select;
 reg axi_shared;
 wire cpu_rom=dreq && da<16384;
 wire cpu_ram=dreq && da>=32'h10000000 && da<32'h10002000;
 wire cpu_shared=dreq && da>=32'h20000000 && da<32'h20001000;
 wire [31:0] cpu_rdata=data_select==0 ? rom_data :
                        data_select==1 ? ram_data :
                        data_select==2 ? shared_cpu_data : dr;
 assign s_axi_rdata=axi_shared ? shared_axi_data : axi_reg_data;
 reg request,complete;
 reg [4:0] gpio;
 // Level-sensitive IRQ: host sets request; firmware clears it in the ISR.
 // Do not turn this into a one-cycle pulse: requests must survive WFI entry.
 reg [31:0] ready,trap_cause,irq_count;
 wire cpu_sleeping;
 assign led6_green_n=~gpio[0];
 assign data_gpio=gpio[4:1];
 reg led_clock_enable;
 reg [6:0] led_rate_hz;
 wire led_clock;
 wire led_resetn=rstn && led_clock_enable;
 reg [24:0] led_counter;
 reg [6:0] led_rate_seen;
 // Phase accumulator: 2*rate edges per 25,000,000 source cycles.
 // Non-divisor rates retain exact average frequency; edge jitter <= one cycle.
 wire [25:0] led_phase_next={1'b0,led_counter}+{18'd0,led_rate_hz,1'b0};
 reg led_red;
 // Gate only the LED peripheral clock. Ibex/AXI/IRQ keep their 25 MHz clock.
 BUFGCE led_clock_gate(.I(clk), .CE(led_clock_enable), .O(led_clock));
 always @(posedge led_clock or negedge led_resetn) begin
   if(!led_resetn) begin led_counter<=0; led_red<=0; led_rate_seen<=0; end
   else if(led_rate_seen!=led_rate_hz) begin
     led_counter<=0; led_red<=0; led_rate_seen<=led_rate_hz;
   end else if(led_phase_next>=2*LED_HALF_PERIOD) begin
     led_counter<=led_phase_next-2*LED_HALF_PERIOD; led_red<=~led_red;
   end else led_counter<=led_phase_next[24:0];
 end
 assign led6_red_n=~led_red;
 ibex_cpu core (
   .clk(clk),.resetn(rstn),.irq_external(request),.sleeping(cpu_sleeping),.instr_req(ireq),.instr_gnt(rstn),
   .instr_rvalid(iv),.instr_addr(ia),.instr_rdata(ir),.instr_err(ie),
   .data_req(dreq),.data_we(dwe),.data_be(dbe),.data_addr(da),.data_wdata(dw),
   .data_gnt(rstn),.data_rvalid(dv),.data_rdata(cpu_rdata),.data_err(de),.fault(cpu_fault)
 );
 integer lane;
 // Dedicated synchronous memory outputs keep the Vivado 2015 BRAM templates.
 always @(posedge clk) if(ireq) ir<=rom[ia[13:2]];
 always @(posedge clk) if(rstn && cpu_rom) rom_data<=rom[da[13:2]];
 always @(posedge clk) if(rstn && cpu_ram) begin
   ram_data<=ram[da[12:2]];
   if(dwe) for(lane=0;lane<4;lane=lane+1)
     if(dbe[lane]) ram[da[12:2]][lane*8+:8]<=dw[lane*8+:8];
 end
 always @(posedge clk) begin
   iv<=rstn && ireq;
   ie<=ireq && ia>=16384;
   dv<=rstn && dreq;
   de<=0;
   if(rstn && dreq) begin
     data_select<=3;
     if(da<16384) begin
       data_select<=0;
       de<=dwe;
     end else if(da>=32'h10000000 && da<32'h10002000) begin
       data_select<=1;
     end else if(da>=32'h20000000 && da<32'h20001000) begin
       data_select<=2;
     end else if(da>=32'h30000000 && da<32'h30000040) begin
       case(da[5:2])
         0:dr<={31'd0,request};
         1:dr<={31'd0,complete};
         2:dr<=ready;
         4:dr<={27'd0,gpio};
         5:dr<=trap_cause;
         7:dr<=irq_count;
         9:dr<={31'd0,led_clock_enable};
         10:dr<={25'd0,led_rate_hz};
         default:dr<=0;
       endcase
     end else begin dr<=0; de<=1; end
   end
 end
 reg aw_hold,w_hold;
 reg [12:0] aw_addr;
 reg [31:0] w_data;
 reg [3:0] w_strb;
 wire wr=aw_hold && w_hold && !s_axi_bvalid && !(s_axi_rvalid && axi_shared);
 wire cpu_reg_write=rstn && dreq && dwe && dbe[0] &&
                    da>=32'h30000000 && da<32'h30000040;
 assign s_axi_awready=rstn && !aw_hold && !s_axi_bvalid;
 assign s_axi_wready=rstn && !w_hold && !s_axi_bvalid;
 assign s_axi_arready=rstn && !s_axi_rvalid && !wr;
 wire shared_write=rstn && wr && aw_addr>=13'h1000 && aw_addr[1:0]==0;
 wire shared_read=s_axi_arvalid && s_axi_arready && s_axi_araddr[12] && s_axi_araddr[1:0]==0;
 ibex_shared_ram shared_ram (
   .clk(clk), .cpu_en(rstn && cpu_shared), .cpu_we(dwe), .cpu_be(dbe),
   .cpu_addr(da[11:2]), .cpu_wdata(dw), .cpu_rdata(shared_cpu_data),
   .ps_en(shared_read || shared_write), .ps_we(shared_write), .ps_be(w_strb),
   .ps_addr(shared_write ? aw_addr[11:2] : s_axi_araddr[11:2]),
   .ps_wdata(w_data), .ps_rdata(shared_axi_data)
 );
 always @(posedge clk) begin
   if(!rstn) begin
     aw_hold<=0; w_hold<=0; s_axi_bvalid<=0; s_axi_rvalid<=0;
     s_axi_bresp<=0; s_axi_rresp<=0; axi_reg_data<=0; axi_shared<=0;
     request<=0; complete<=0; ready<=0; gpio<=0; trap_cause<=0; irq_count<=0;
     led_clock_enable<=0;
     led_rate_hz<=1;
   end else begin
     if(s_axi_awvalid && s_axi_awready) begin aw_hold<=1; aw_addr<=s_axi_awaddr[12:0]; end
     if(s_axi_wvalid && s_axi_wready) begin w_hold<=1; w_data<=s_axi_wdata; w_strb<=s_axi_wstrb; end
     if(s_axi_bvalid && s_axi_bready) s_axi_bvalid<=0;
     if(wr) begin
       aw_hold<=0; w_hold<=0; s_axi_bvalid<=1; s_axi_bresp<=0;
       if(aw_addr[1:0]!=0) s_axi_bresp<=2;
       else if(aw_addr>=13'h1000) begin
         // Shared BRAM port writes above.
       end else case(aw_addr)
         0:if(w_strb[0]) request<=w_data[0];
         4:if(w_strb[0]) complete<=w_data[0];
         default:s_axi_bresp<=2;
       endcase
     end
     // Firmware owns GPIO. CPU completion wins over a simultaneous host clear.
     if(cpu_reg_write) case(da[5:2])
       0:request<=dw[0];
       1:complete<=dw[0];
       2:ready<=dw;
       4:gpio<=dw[4:0];
       5:trap_cause<=dw;
       7:irq_count<=dw; // Firmware-owned diagnostic IRQ counter.
       9:led_clock_enable<=dw[0];
       10:if(dw>=1 && dw<=100) led_rate_hz<=dw[6:0];
     endcase
     if(s_axi_rvalid && s_axi_rready) s_axi_rvalid<=0;
     if(s_axi_arvalid && s_axi_arready) begin
       axi_shared<=s_axi_araddr[12] && s_axi_araddr[1:0]==0;
       s_axi_rvalid<=1; s_axi_rresp<=0;
       if(s_axi_araddr[1:0]!=0) begin axi_reg_data<=0; s_axi_rresp<=2; end
       else if(s_axi_araddr[12]) begin end
       else case(s_axi_araddr[12:0])
         0:axi_reg_data<={31'd0,request};
         4:axi_reg_data<={31'd0,complete};
         8:axi_reg_data<=ready;
         16:axi_reg_data<={27'd0,gpio};
         20:axi_reg_data<=trap_cause;
         24:axi_reg_data<={31'd0,cpu_fault};
         28:axi_reg_data<=irq_count;
         32:axi_reg_data<={31'd0,cpu_sleeping};
         36:axi_reg_data<={31'd0,led_clock_enable};
         40:axi_reg_data<={25'd0,led_rate_hz};
         default:begin axi_reg_data<=0; s_axi_rresp<=2; end
       endcase
     end
   end
 end
endmodule
