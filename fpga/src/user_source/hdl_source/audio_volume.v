// Signed PCM attenuation; both HDMI and the meter use these same samples.
module audio_volume(
    input [23:0] left_in,right_in,
    input [2:0] volume,
    output [23:0] left_out,right_out
);
    function [23:0] attenuate;
        input signed [23:0] sample;
        input [2:0] level;
        reg signed [25:0] wide;
        begin
            wide={{2{sample[23]}},sample};
            case(level)
                0:attenuate=0;
                1:attenuate=wide >>> 2;
                2:attenuate=wide >>> 1;
                3:attenuate=(wide+(wide <<< 1)) >>> 2;
                default:attenuate=sample;
            endcase
        end
    endfunction
    assign left_out=attenuate(left_in,volume);
    assign right_out=attenuate(right_in,volume);
endmodule
