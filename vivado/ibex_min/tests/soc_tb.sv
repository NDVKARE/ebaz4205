`timescale 1ns/1ps
module soc_tb;
 reg clk=0, resetn=0;
 always #20 clk=~clk;
 reg [31:0] awaddr=0,wdata=0,araddr=0;
 reg [3:0] wstrb=15;
 reg awvalid=0,wvalid=0,bready=0,arvalid=0,rready=0;
 wire awready,wready,bvalid,arready,rvalid,green,red,fault;
 wire [1:0] bresp,rresp;
 wire [31:0] rdata;
 wire [3:0] data_gpio;
 ibex_soc #(.LED_HALF_PERIOD(128)) dut(.clk(clk),.resetn(resetn),.s_axi_awaddr(awaddr),
   .s_axi_awvalid(awvalid),.s_axi_awready(awready),.s_axi_wdata(wdata),
   .s_axi_wstrb(wstrb),.s_axi_wvalid(wvalid),.s_axi_wready(wready),
   .s_axi_bresp(bresp),.s_axi_bvalid(bvalid),.s_axi_bready(bready),
   .s_axi_araddr(araddr),.s_axi_arvalid(arvalid),.s_axi_arready(arready),
   .s_axi_rdata(rdata),.s_axi_rresp(rresp),.s_axi_rvalid(rvalid),.s_axi_rready(rready),
   .led6_green_n(green),.led6_red_n(red),.data_gpio(data_gpio),.cpu_fault(fault));
 task automatic write32(input [31:0] addr,input [31:0] value);
   @(negedge clk); awaddr=addr; awvalid=1;
   do @(posedge clk); while(!awready);
   @(negedge clk); awvalid=0;
   // Deliberately send W after AW, not in the same cycle.
   repeat(2) @(negedge clk);
   wdata=value; wvalid=1;
   do @(posedge clk); while(!wready);
   @(negedge clk); wvalid=0;
   wait(bvalid);
   if(bresp!=0) $fatal(1,"AXI write error %h",addr);
   repeat(2) @(negedge clk);
   bready=1; @(negedge clk); bready=0;
 endtask
 task automatic read32(input [31:0] addr,output [31:0] value);
   @(negedge clk); araddr=addr; arvalid=1;
   do @(posedge clk); while(!arready);
   @(negedge clk); arvalid=0;
   wait(rvalid);
   value=rdata;
   repeat(2) begin @(negedge clk); if(!rvalid || rdata!==value) $fatal(1,"Read backpressure"); end
   if(rresp!=0) $fatal(1,"AXI read error %h",addr);
   rready=1; @(negedge clk); rready=0;
 endtask
 task automatic request(input [7:0] protocol,id,input [31:0] length,a0,a1);
   reg [31:0] v;
   write32(4,0);
   write32('h1004,0);
   write32('h1014,length);
   write32('h1018,(7<<18)|(protocol<<10)|id);
   write32('h101c,a0); write32('h1020,a1);
   write32(0,1);
   do read32(4,v); while(v==0);
   read32('h1004,v); if(v!=1) $fatal(1,"Channel not free");
   read32('h1018,v); if(v!=((7<<18)|(protocol<<10)|id)) $fatal(1,"Token changed");
 endtask
 reg [31:0] v;
 task automatic set_rate(input [31:0] rate,high_word,flags,clock_id,length,expected_status);
   write32('h1024,rate); write32('h1028,high_word);
   request('h14,5,length,flags,clock_id);
   read32('h101c,v); if(v!=expected_status) $fatal(1,"RATE_SET status rate=%d status=%h",rate,v);
 endtask
 task automatic check_rate(input integer rate);
   reg previous_red;
   integer transitions;
   // One simulated second = 256 clocks, so exactly 2*rate edges per second.
   repeat(2) @(negedge clk);
   previous_red=red; transitions=0;
   repeat(256) begin
     @(negedge clk);
     if(red!==previous_red) transitions=transitions+1;
     previous_red=red;
   end
   if(transitions!=2*rate) $fatal(1,"Wrong blink frequency rate=%d edges=%d",rate,transitions);
 endtask
 task automatic check_sleep;
   repeat(250) @(negedge clk);
   if(!dut.cpu_sleeping || dut.ireq || dut.dreq) $fatal(1,"Ibex not idle in WFI");
   repeat(20) begin
     @(negedge clk);
     if(!dut.cpu_sleeping || dut.ireq || dut.dreq) $fatal(1,"Idle CPU still polling");
   end
 endtask
 initial begin
   repeat(4) @(negedge clk); resetn=1;
   do read32(8,v); while(v!='h49424558);
   if(!green || !red || data_gpio!==0) $fatal(1,"GPIO initial state");
   check_sleep();
   read32(28,v); if(v!=0) $fatal(1,"IRQ before request");
   // Byte strobes must preserve the other bytes in shared BRAM.
   write32('h1ff0,'h11223344);
   wstrb=4'b0101; write32('h1ff0,'haabbccdd); wstrb=15;
   read32('h1ff0,v); if(v!='h11bb33dd) $fatal(1,"Shared byte strobes");
   // Queue a write while a shared-memory read response is held.
   @(negedge clk); araddr='h1ff0; arvalid=1;
   do @(posedge clk); while(!arready);
   @(negedge clk); arvalid=0;
   wait(rvalid);
   @(negedge clk); awaddr='h1ff0; awvalid=1; wdata='h12345678; wvalid=1;
   do @(posedge clk); while(!(awready && wready));
   @(negedge clk); awvalid=0; wvalid=0;
   repeat(4) begin
     @(negedge clk);
     if(!rvalid || rdata!='h11bb33dd || bvalid) $fatal(1,"Concurrent AXI read/write");
   end
   rready=1; @(negedge clk); rready=0;
   wait(bvalid); if(bresp!=0) $fatal(1,"Queued write error");
   @(negedge clk); bready=1; @(negedge clk); bready=0;
   read32('h1ff0,v); if(v!='h12345678) $fatal(1,"Queued write lost");
   request('h10,0,4,0,0);
   read32('h101c,v); if(v!=0) $fatal(1,"Base status");
   read32('h1020,v); if(v!='h20000) $fatal(1,"Base version");
   request('h10,1,4,0,0);
   read32('h1020,v); if(v!='h202) $fatal(1,"Base attributes");
   request('h10,6,8,0,0);
   read32('h1020,v); if(v!=2) $fatal(1,"Protocol count");
   read32('h1024,v); if(v!='h8014) $fatal(1,"Clock and GPIO protocols");
   request('h10,7,8,'hffffffff,0);
   read32('h1020,v); if(v!=1) $fatal(1,"Agent identity");
   request('h80,3,12,0,1);
   read32('h101c,v); if(v!=0 || green) $fatal(1,"GPIO on");
   request('h80,4,8,0,0);
   read32('h1020,v); if(v!=1) $fatal(1,"GPIO get");
   request('h80,3,12,0,0);
   read32('h101c,v); if(v!=0 || !green) $fatal(1,"GPIO off");
   request('h80,3,8,0,1);
   read32('h101c,v); if(v!='hfffffffe || !green) $fatal(1,"Truncated request");
   request('h80,3,12,0,2);
   read32('h101c,v); if(v!='hfffffffe) $fatal(1,"Invalid GPIO value");
   request('h80,4,8,5,0);
   read32('h101c,v); if(v!='hfffffffd) $fatal(1,"Invalid GPIO id");
   request('h55,0,4,0,0);
   read32('h101c,v); if(v!='hffffffff) $fatal(1,"Unknown protocol");
   check_sleep();
   read32(28,v); if(v!=11) $fatal(1,"Lost or duplicate IRQ: %d",v);
   // Doorbell on a free channel must be acknowledged without a bogus response.
   write32(4,0); write32(0,1);
   check_sleep();
   read32(0,v); if(v!=0) $fatal(1,"IRQ not cleared");
   read32(4,v); if(v!=0) $fatal(1,"Spurious completion");
   read32(28,v); if(v!=12) $fatal(1,"Spurious doorbell IRQ count");
   // Repeated requests check mret restores interrupt enable and stack/registers.
   repeat(20) begin
     request('h80,4,8,0,0);
     read32('h1020,v); if(v!=0) $fatal(1,"Repeated GPIO GET");
   end
   check_sleep();
   read32(28,v); if(v!=32) $fatal(1,"Repeated IRQ count");
   // Set each output, proving one SET preserves all other bits including LED6.
   request('h80,1,4,0,0);
   read32('h1020,v); if(v!=5) $fatal(1,"GPIO count");
   request('h80,3,12,0,1);
   request('h80,3,12,1,1);
   if(data_gpio!==4'b0001 || green) $fatal(1,"DATA GPIO1");
   request('h80,3,12,2,1);
   if(data_gpio!==4'b0011 || green) $fatal(1,"DATA GPIO2 preservation");
   request('h80,3,12,3,1);
   if(data_gpio!==4'b0111 || green) $fatal(1,"DATA GPIO3 preservation");
   request('h80,3,12,4,1);
   if(data_gpio!==4'b1111 || green) $fatal(1,"DATA GPIO4 preservation");
   request('h80,3,12,2,0);
   if(data_gpio!==4'b1101 || green) $fatal(1,"DATA GPIO2 off preservation");
   request('h80,4,8,2,0);
   read32('h1020,v); if(v!=0) $fatal(1,"DATA GPIO2 GET");
   request('h80,4,8,4,0);
   read32('h1020,v); if(v!=1) $fatal(1,"DATA GPIO4 GET");
   request('h80,3,12,5,1);
   read32('h101c,v);
   if(v!='hfffffffd || data_gpio!==4'b1101 || green) $fatal(1,"Invalid SET changed outputs");
   check_sleep();
   read32(28,v); if(v!=42) $fatal(1,"Multi-GPIO IRQ count");
   request('h14,0,4,0,0);
   read32('h1020,v); if(v!='h10000) $fatal(1,"Clock protocol version");
   request('h14,3,8,0,0);
   read32('h1020,v); if(v!=0 || !red) $fatal(1,"Clock initial attributes");
   request('h14,6,8,0,0);
   read32('h1020,v); if(v!=1) $fatal(1,"Clock rate");
   read32('h1024,v); if(v!=0) $fatal(1,"Clock rate high word");
   request('h14,4,12,0,0);
   read32('h1020,v); if(v!='h1003) $fatal(1,"Clock rate range flags");
   read32('h1024,v); if(v!=1) $fatal(1,"Clock described rate");
   read32('h102c,v); if(v!=100) $fatal(1,"Clock max rate");
   read32('h1034,v); if(v!=1) $fatal(1,"Clock rate step");
   request('h14,7,12,0,1);
   read32(36,v); if(v!=1) $fatal(1,"Clock enable register");
   begin : check_blink
     reg previous_red;
     integer transitions;
     previous_red=red; transitions=0;
     repeat(800) begin
       @(negedge clk);
       if(red!==previous_red) transitions=transitions+1;
       previous_red=red;
     end
     if(transitions<2) $fatal(1,"Red LED clock not blinking");
   end
   // GPIO traffic and WFI still work with the red peripheral clock enabled.
   request('h80,4,8,4,0);
   read32('h1020,v); if(v!=1) $fatal(1,"GPIO while LED clock enabled");
   check_sleep();
   request('h14,3,8,0,0);
   read32('h1020,v); if(v!=1) $fatal(1,"Clock enabled attributes");
   request('h14,7,12,1,0);
   read32('h101c,v); if(v!='hfffffffd) $fatal(1,"Invalid clock ID");
   request('h14,7,12,0,2);
   read32('h101c,v); if(v!='hfffffffe) $fatal(1,"Invalid clock flags");
   read32(36,v); if(v!=1) $fatal(1,"Invalid request changed clock");
   request('h14,7,8,0,0);
   read32('h101c,v); if(v!='hfffffffe) $fatal(1,"Truncated clock request");
   request('h14,7,12,0,0);
   repeat(100) begin @(posedge clk); #1; if(!red || dut.led_clock) $fatal(1,"Disabled clock still active"); end
   request('h14,3,8,0,0);
   read32('h1020,v); if(v!=0) $fatal(1,"Clock disabled attributes");
   set_rate(10,0,0,0,20,0);
   read32(40,v); if(v!=10 || !red) $fatal(1,"Set while gated");
   request('h14,6,8,0,0);
   read32('h1020,v); if(v!=10) $fatal(1,"Rate readback while gated");
   request('h14,7,12,0,1);
   read32(36,v); if(v!=1) $fatal(1,"Clock cannot re-enable");
   check_rate(10);
   for(integer rate=1;rate<=100;rate=rate+1) begin
     set_rate(rate,0,0,0,20,0);
     request('h14,6,8,0,0);
     read32('h1020,v); if(v!=rate) $fatal(1,"Rate readback");
     check_rate(rate);
   end
   set_rate(0,0,0,0,20,'hfffffffe);
   set_rate(101,0,0,0,20,'hfffffffe);
   set_rate(10,1,0,0,20,'hfffffffe);
   set_rate(10,0,1,0,20,'hfffffffe);
   set_rate(10,0,0,1,20,'hfffffffd);
   set_rate(10,0,0,0,16,'hfffffffe);
   read32(40,v); if(v!=100) $fatal(1,"Invalid request changed rate");
   read32(36,v); if(v!=1) $fatal(1,"RATE_SET changed enable");
   request('h14,7,12,0,0);
   request('h10,6,8,1,0);
   read32('h1020,v); if(v!=1) $fatal(1,"Protocol skip count");
   read32('h1024,v); if(v!='h80) $fatal(1,"Protocol skip GPIO");
   request('h10,6,8,2,0);
   read32('h1020,v); if(v!=0) $fatal(1,"Protocol list end");
   check_sleep();
   read32(20,v); if(v!=0 || fault || !red) $fatal(1,"CPU trap/fault");
   $display("PASS: SCMI Clock discovery/attributes/rate/enable/disable/re-enable/errors; red LED clock gate; 5 GPIOs; WFI and AXI regression");
   $finish;
 end
 initial begin #40000000; $fatal(1,"Timeout waiting for Ibex SCMI server"); end
endmodule
