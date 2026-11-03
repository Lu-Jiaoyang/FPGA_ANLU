// Left to right decimal score; F means blank to seg_scan8.
module score_digits(input wire [7:0] score, output reg [11:0] digits);
    always @* case(score)
        8'd0: digits=12'hff0;
        8'd25: digits=12'hf52;
        8'd50: digits=12'hf05;
        8'd75: digits=12'hf57;
        8'd100: digits=12'h001;
        default: digits=12'hfee;
    endcase
endmodule
