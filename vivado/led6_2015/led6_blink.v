`timescale 1ns/1ps
module led6_blink (
    input wire clk25,
    output reg led6_green_n = 1'b1,
    output wire led6_red_n
);
    reg [23:0] count = 24'd0;
    assign led6_red_n = 1'b1;
    always @(posedge clk25) begin
        if (count == 24'd12499999) begin
            count <= 24'd0;
            led6_green_n <= ~led6_green_n;
        end else begin
            count <= count + 1'b1;
        end
    end
endmodule
