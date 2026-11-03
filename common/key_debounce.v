// Active-low push-button synchronizer, debounce filter and one-cycle press pulse.
module key_debounce #(
    parameter integer CLK_FREQ_HZ = 50000000,
    parameter integer DEBOUNCE_MS = 20
) (
    input  wire clk,
    input  wire rst_n,
    input  wire key_n,
    output reg  pressed
);
    localparam integer COUNT_MAX = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;
    localparam integer COUNT_W = (COUNT_MAX < 2) ? 1 : $clog2(COUNT_MAX + 1);
    reg sync0, sync1, stable;
    reg [COUNT_W-1:0] count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync0  <= 1'b1;
            sync1  <= 1'b1;
            stable <= 1'b1;
            count  <= {COUNT_W{1'b0}};
            pressed <= 1'b0;
        end else begin
            sync0 <= key_n;
            sync1 <= sync0;
            pressed <= 1'b0;
            if (sync1 == stable) begin
                count <= {COUNT_W{1'b0}};
            end else if (count == COUNT_MAX - 1) begin
                stable <= sync1;
                count <= {COUNT_W{1'b0}};
                if (stable == 1'b1 && sync1 == 1'b0)
                    pressed <= 1'b1;
            end else begin
                count <= count + 1'b1;
            end
        end
    end
endmodule
