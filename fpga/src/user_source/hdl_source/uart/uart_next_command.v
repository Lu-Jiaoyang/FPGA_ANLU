// One command for external image browsing: A5 = next image.
// Run directly on the image controller clock, so no command CDC is needed.
module uart_next_command #(
    parameter integer CLK_FRE = 100,
    parameter integer BAUD_RATE = 115200
)(
    input  wire clk,
    input  wire rst,
    input  wire rx_pin,
    output wire next_pulse,
    output reg  received_led
);
    reg [1:0] reset_pipe;
    always @(posedge clk or posedge rst) begin
        if (rst) reset_pipe <= 2'b00;
        else     reset_pipe <= {reset_pipe[0], 1'b1};
    end
    wire run_n = reset_pipe[1];
    wire [7:0] rx_data;
    wire rx_valid;

    uart_rx #(.CLK_FRE(CLK_FRE), .BAUD_RATE(BAUD_RATE)) u_rx (
        .clk(clk), .rst_n(run_n), .rx_pin(rx_pin),
        .rx_data(rx_data), .rx_data_valid(rx_valid), .rx_data_ready(1'b1)
    );
    assign next_pulse = run_n && rx_valid && (rx_data == 8'hA5);

    // Receipt indicator only; the image may still be scanning/loading.
    always @(posedge clk or negedge run_n) begin
        if (!run_n) received_led <= 1'b0;
        else if (next_pulse) received_led <= ~received_led;
    end
endmodule
