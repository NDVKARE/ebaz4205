`timescale 1ns/1ps
module led6_blink_tb;
    reg clk25 = 0;
    wire green_n, red_n;
    integer cycle;
    reg expected;
    led6_blink dut (.clk25(clk25), .led6_green_n(green_n), .led6_red_n(red_n));
    always #20 clk25 = ~clk25;
    initial begin
        for (cycle = 1; cycle <= 25000001; cycle = cycle + 1) begin
            @(posedge clk25);
            #1;
            expected = (cycle < 12500000 || cycle >= 25000000);
            if (green_n !== expected || red_n !== 1'b1) begin
                $display("FAIL: cycle %0d green=%b red=%b", cycle, green_n, red_n);
                $finish;
            end
        end
        $display("PASS: exact 12,500,000-cycle half-period, red stays off");
        $finish;
    end
endmodule
