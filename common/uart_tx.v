module uart_tx #(
    parameter integer CLK_FREQ_HZ = 50000000,
    parameter integer BAUD = 9600
) (
    input wire clk, input wire rst_n, input wire start, input wire [7:0] data,
    output reg tx, output reg busy
);
    localparam integer CLKS_PER_BIT = CLK_FREQ_HZ / BAUD;
    reg [31:0] count;
    reg [3:0] bit_index;
    reg [9:0] frame;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin tx <= 1'b1; busy <= 1'b0; count <= 0; bit_index <= 0; frame <= 10'h3ff; end
        else if (!busy) begin
            tx <= 1'b1; count <= 0; bit_index <= 0;
            if (start) begin frame <= {1'b1, data, 1'b0}; busy <= 1'b1; tx <= 1'b0; end
        end else if (count == CLKS_PER_BIT - 1) begin
            count <= 0;
            if (bit_index == 4'd9) begin busy <= 1'b0; tx <= 1'b1; end
            else begin bit_index <= bit_index + 1'b1; tx <= frame[bit_index + 1'b1]; end
        end else count <= count + 1'b1;
    end
endmodule
