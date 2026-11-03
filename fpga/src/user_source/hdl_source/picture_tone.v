// Lesson 13: signed contrast about mid-gray, saturation, then brightness.
// Gain steps are exact quarters: 4 = 100%, 0..8 = 0..200%.
module picture_tone(
    input [23:0] rgb,
    input [3:0] bright,contrast,
    input [4:0] fade,
    output [23:0] adjusted
);
    function [7:0] channel;
        input [7:0] value;
        input [3:0] b,c;
        input [4:0] f;
        reg signed [8:0] centered;
        reg signed [13:0] product;
        reg signed [13:0] shifted;
        reg [7:0] contrasted,lit;
        reg [11:0] bright_product;
        reg [12:0] faded;
        begin
            centered=$signed({1'b0,value})-9'sd128;
            product=centered*$signed({1'b0,c});
            shifted=(product >>> 2)+14'sd128;
            contrasted=shifted<0 ? 8'd0 : shifted>255 ? 8'd255 : shifted[7:0];
            bright_product=contrasted*b;
            lit=bright_product>12'd1023 ? 8'd255 : bright_product[9:2];
            faded=lit*f;
            channel=faded[11:4];
        end
    endfunction
    assign adjusted={channel(rgb[23:16],bright,contrast,fade),
                     channel(rgb[15:8],bright,contrast,fade),
                     channel(rgb[7:0],bright,contrast,fade)};
endmodule
