// Active-low {dp,g,f,e,d,c,b,a}, active-low digit selects.
// digits[3:0] belongs to seg_sel[0]. F=blank, other values=hex digits.
// Blank digit selects for one clock while changing segment data.
module seg_scan8 #(
    parameter integer CLK_FREQ_HZ = 50000000,
    parameter integer FRAME_HZ = 100
)(
    input wire clk,
    input wire rst_n,
    input wire [31:0] digits,
    output reg [7:0] seg_sel,
    output reg [7:0] seg_data
);
    localparam integer RAW_CYCLES = CLK_FREQ_HZ / (FRAME_HZ * 8);
    localparam integer SLOT_CYCLES = (RAW_CYCLES < 3) ? 3 : RAW_CYCLES;
    localparam integer COUNT_W = $clog2(SLOT_CYCLES);
    reg [COUNT_W-1:0] count;
    reg [2:0] index;
    function [7:0] decode;
        input [3:0] value;
        begin
            case (value)
                0: decode=8'hC0; 1: decode=8'hF9; 2: decode=8'hA4;
                3: decode=8'hB0; 4: decode=8'h99; 5: decode=8'h92;
                6: decode=8'h82; 7: decode=8'hF8; 8: decode=8'h80;
                9: decode=8'h90; 10: decode=8'h88; 11: decode=8'h83;
                12: decode=8'hC6; 13: decode=8'hA1; 14: decode=8'h86;
                default: decode=8'hFF;
            endcase
        end
    endfunction
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= 0;
            index <= 0;
            seg_sel <= 8'hFF;
            seg_data <= 8'hFF;
        end else begin
            if (count == 0) begin
                seg_sel <= 8'hFF;
                seg_data <= decode(digits >> (index * 4));
            end else if (count == 1) begin
                seg_sel <= ~(8'b1 << index);
            end
            if (count == SLOT_CYCLES - 1) begin
                count <= 0;
                index <= index + 1'b1;
            end else count <= count + 1'b1;
        end
    end
endmodule
