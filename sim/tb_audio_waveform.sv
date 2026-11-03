`timescale 1ns/1ps
module tb_audio_waveform;
    reg clk=0,rst=1,hs=1,vs=1,de=0,enable=0,pcm_valid=0;
    reg [23:0] pcm_left=0;
    wire ho,vo,dout;
    wire [23:0] out;
    reg passed=0;
    integer frames=0,pixel_checks=0;
    integer expected_peaks[0:3];
    always #5 clk=~clk;
    audio_waveform_overlay dut(clk,rst,hs,vs,de,24'h010203,enable,pcm_valid,pcm_left,ho,vo,dout,out,1'b0);
    task check(input bit ok,input string msg);
        if(!ok) $fatal(1,"side bars: %s",msg);
    endtask
    task sample(input integer value);
        begin
            @(negedge clk);pcm_left=24'(value);pcm_valid=1;
            @(negedge clk);pcm_valid=0;
        end
    endtask
    task boundary(input bit valid,input integer peak);
        begin
            @(negedge clk);de=0;vs=1;repeat(4) @(negedge clk);vs=0;
            repeat(3) @(negedge clk);vs=1;repeat(3) @(negedge clk);
            for(integer n=0;n<3;n++) expected_peaks[n]=valid ? expected_peaks[n+1] : 0;
            expected_peaks[3]=valid ? peak : 0;
            for(integer n=0;n<4;n++) check(dut.peak_history[n]==expected_peaks[n],"frame history committed atomically");
        end
    endtask
    task capture(input integer amplitude);
        integer value;
        begin
            for(integer n=0;n<400;n++) begin
                value=(n/12)%2 ? -amplitude : amplitude;
                sample(value);
            end
            check(dut.capture_count==32,"complete decimated capture");
        end
    endtask
    task raster(input bit shown,input bit valid,input bit disable_midframe,input string filename);
        integer length,fd,sx,sy;
        reg [127:0] spectrum_snapshot;
        reg [23:0] expected;
        reg [23:0] color;
        begin
            spectrum_snapshot=dut.spectrum_frame;
            fd=filename!="" ? $fopen(filename,"w") : 0;
            for(integer yy=0;yy<480;yy++) begin
                for(integer xx=0;xx<640;xx++) begin
                    @(negedge clk);de=1;
                    if(disable_midframe && yy==100 && xx==0) enable=0;
                    expected=24'h010203;
                    for(integer n=0;n<4;n++) begin
                        length=expected_peaks[n]==0 ? 0 : expected_peaks[n]<64 ? 16 :
                            expected_peaks[n]<128 ? 32 : expected_peaks[n]<192 ? 48 : 64;
                        case(n)
                            0:color=24'h168aff;1:color=24'h18d9ff;2:color=24'h20ffb0;3:color=24'hffc040;
                        endcase
                        if(shown && valid && yy>=240+32*n && yy<264+32*n && (yy-240)%8<6 &&
                            ((xx>=8 && xx<8+length) || (xx>=632-length && xx<632)) && (xx<80 ? (xx-8)%8 : (631-xx)%8)<6) expected=color;
                    end
                    sx=xx<80 ? xx-8 : xx-568;sy=439-yy;
                    // The removed lower-right spectrum must pass the original pixels through.
                    @(posedge clk);#1;
                    if(dut.spectrum_frame!==spectrum_snapshot) $fatal(1,"spectrum tearing");
                    if(!dout || ho!==hs || vo!==vs || out!==expected)
                        $fatal(1,"bar pixel frame%0d (%0d,%0d) expected%h actual%h",frames,xx,yy,expected,out);
                    pixel_checks++;
                    if(fd) $fdisplay(fd,"%06h",out);
                end
                @(negedge clk);de=0;hs=0;
                @(posedge clk);#1;check(!dout && !ho && out==0,"blanking/sync aligned");
                repeat(3) @(negedge clk);hs=1;
            end
            if(fd) $fclose(fd);frames++;
        end
    endtask
    task amplitude_case(input integer amplitude,input integer expected_level);
        integer peak;
        begin
            peak=amplitude/8192;if(peak>255) peak=255;
            capture(amplitude);boundary(1,peak);
            check(dut.quantized_peak==expected_level,"four levels derived from real magnitude");
            check(dut.capture_peak==0,"new frame clears meter");
            raster(1,1,0,amplitude==1600000 ? "sim/render_square_bars.hex" : "");
        end
    endtask
    initial begin
        for(integer n=0;n<4;n++) expected_peaks[n]=0;
        repeat(5) @(negedge clk);rst=0;boundary(0,0);
        raster(0,0,0,"");
        enable=1;repeat(4) @(negedge clk);boundary(0,0);
        raster(1,0,0,"");
        amplitude_case(100000,64);amplitude_case(600000,128);
        amplitude_case(1100000,192);amplitude_case(1600000,255);
        amplitude_case(0,0);amplitude_case(2000000,255);
        // The loudest negative 24-bit value must saturate instead of wrapping to zero.
        repeat(400) sample(-8388608);
        boundary(1,255);check(dut.display_peak==255,"negative full-scale saturation");
        raster(1,1,0,"");
        // A brief peak between decimated samples must still be metered.
        repeat(400) sample(0);sample(1600000);
        boundary(1,195);check(dut.display_peak==195,"meter uses every sample after capture is full");
        // Collecting the next frame cannot modify any of the currently displayed rectangles.
        repeat(400) sample(0);
        raster(1,1,0,"");boundary(1,0);raster(1,1,0,"");
        repeat(100) sample(2000000);boundary(0,0);
        check(!dut.display_valid && dut.display_peak==0,"partial capture hidden, no stale loud peak");
        raster(1,0,0,"");amplitude_case(100000,64);
        capture(600000);boundary(1,73);raster(1,1,1,"");
        boundary(0,0);check(!dut.enabled_frame,"disable at frame boundary");raster(0,0,0,"");
        enable=1;repeat(4) @(negedge clk);boundary(0,0);amplitude_case(0,0);
        // Check both sides of every quantization threshold, including a skipped-sample impulse.
        foreach(expected_peaks[n]) begin
            capture((64*n+63)*8192);sample((64*n+64)*8192);
            boundary(1,n==3 ? 255 : 64*n+64);
            check(dut.quantized_peak==(n>=2 ? 255 : 64*(n+2)),"threshold enters next width");
            raster(1,1,0,"");
        end
        force dut.spectrum_ready=1;
        force dut.spectrum_levels=128'hffe0c0a08060402020406080a0c0e0ff;
        boundary(0,0);raster(1,0,0,"sim/render_spectrum.hex");
        $display("ALL RIGHT SPECTRUM REMOVAL TESTS PASSED: forced nonzero spectrum, full raster original pixels and retained side blocks");
        release dut.spectrum_levels;release dut.spectrum_ready;
        @(negedge clk);rst=1;@(posedge clk);#1;check(!dout && out==0,"reset blanks output");
        $display("ALL SQUARE BAR TESTS PASSED: %0d full frames, %0d exact pixels, mirrored inward growth, gaps, four levels, history, saturation, sparse PCM and bypass",frames,pixel_checks);
        passed=1;$finish;
    end
    initial begin #100000000;$fatal(1,"waveform watchdog");end
endmodule
