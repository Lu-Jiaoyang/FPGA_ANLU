`timescale 1ns/1ps
module tb_audio_volume;
    reg clk=0,rst=1,vs=1,de=0,valid=0;
    always #5 clk=~clk;
    reg [23:0] left_in=0,right_in=0;
    reg [2:0] volume=4;
    wire [23:0] left_out,right_out,rgb;
    reg passed=0;
    audio_volume dut(left_in,right_in,volume,left_out,right_out);
    audio_waveform_overlay meter(.clk(clk),.rst(rst),.hs(1'b1),.vs(vs),.de(de),
        .rgb(24'h123456),.enable(volume!=0),.pcm_valid(valid),.pcm_left(left_out),
        .hs_out(),.vs_out(),.de_out(),.rgb_out(rgb),.cue_active(1'b0));
    task check(input bit ok,input string msg);if(!ok) $fatal(1,"volume: %s",msg);endtask
    task cycles(input integer n);repeat(n) @(negedge clk);endtask
    task frame;vs=0;cycles(2);vs=1;cycles(2);endtask
    function automatic [23:0] expected(input integer sample,input integer level);
        longint signed wide;
        begin
            wide=sample;
            expected=level>=4 ? sample : (wide*level) >>> 2;
        end
    endfunction
    integer fixtures[9]='{0,1,-1,3,-3,8388607,-8388608,2000000,-2000000};
    integer previous_pixels=-1,pixels;
    initial begin
        for(integer v=0;v<8;v++) begin
            volume=v;
            for(integer i=0;i<1009;i++) begin
                left_in=i<9 ? fixtures[i] : $random;
                right_in=i<9 ? fixtures[8-i] : $random;
                #1;
                check(left_out===expected($signed(left_in),v),"signed left PCM, exact attenuation and no overflow");
                check(right_out===expected($signed(right_in),v),"independent signed right PCM");
            end
        end
        cycles(4);rst=0;left_in=2000000;right_in=-2000000;
        for(integer v=0;v<=4;v++) begin
            volume=v;cycles(5);frame();
            repeat(5) begin valid=1;cycles(400);valid=0;frame();end
            check(meter.display_peak==((2000000*v/4)>>13),"meter measures attenuated PCM peak");
            pixels=0;
            for(integer yy=0;yy<480;yy++) begin
                for(integer xx=0;xx<640;xx++) begin
                    @(negedge clk);de=1;@(posedge clk);#1;
                    if(rgb!=24'h123456) begin
                        pixels++;
                        check(v!=0 && ((xx>=8 && xx<72)||(xx>=568 && xx<632)) && yy>=240 && yy<368,
                            "only original side blocks may cover picture");
                    end
                end
                @(negedge clk);de=0;cycles(2);
            end
            check(pixels>previous_pixels,"each higher volume has strictly more lit square pixels for same PCM");
            if(v==0) check(pixels==0,"mute leaves every image pixel unchanged");
            previous_pixels=pixels;
        end
        volume=0;cycles(5);frame();
        check(!meter.enabled_frame && !meter.display_valid && meter.display_peak==0,"mute clears meter at next frame");
        for(integer n=0;n<4;n++) check(meter.peak_history[n]==0,"mute clears old peaks");
        volume=4;left_in=0;cycles(5);frame();valid=1;cycles(400);valid=0;frame();
        check(meter.display_peak==0,"unmuting silence cannot restore old loud peaks");
        $display("ALL AUDIO VOLUME TESTS PASSED: signed stereo PCM, 5 gains, 1536000 exact image pixels, monotonic blocks and mute history");
        passed=1;$finish;
    end
    initial begin #30000000;$fatal(1,"volume watchdog");end
endmodule
