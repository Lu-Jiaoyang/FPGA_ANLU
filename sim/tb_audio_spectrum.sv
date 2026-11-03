`timescale 1ns/1ps
module tb_audio_spectrum;
    reg clk=0,rst=1,enable=0,valid=0;
    reg [23:0] pcm=0;
    wire [127:0] levels;
    reg [23:0] samples[0:5119];
    reg [127:0] expected[0:9];
    reg [127:0] previous;
    reg passed=0;
    integer windows=0;
    always #20 clk=~clk;
    audio_spectrum16 dut(clk,rst,enable,valid,pcm,levels,);
    task sample(input reg [23:0] value);
        @(negedge clk);valid=1;pcm=value;
        @(negedge clk);valid=0;
        repeat(99) @(negedge clk);
    endtask
    initial begin
        $readmemh("sim/spectrum_pcm.mem",samples);
        $readmemh("sim/spectrum_expected.mem",expected);
        repeat(5) @(negedge clk);rst=0;enable=1;
        for(integer c=0;c<10;c++) begin
            previous=levels;
            for(integer n=0;n<512;n++) begin
                if(dut.state!=0 || dut.sample_index!=n) $fatal(1,"sample not consumed c%0d n%0d",c,n);
                sample(samples[c*512+n]);
                if(n<511 && levels!==previous) $fatal(1,"partial spectrum published");
            end
            if(levels!==expected[c]) $fatal(1,"DFT window%0d got%h expected%h",c,levels,expected[c]);
            windows++;
        end
        repeat(100) sample(24'd1500000);
        @(negedge clk);enable=0;repeat(3) @(negedge clk);
        if(levels!=0 || dut.sample_index!=0) $fatal(1,"disable must discard partial window");
        enable=1;
        for(integer n=0;n<512;n++) sample(samples[n]);
        if(levels!==expected[0]) $fatal(1,"restart contaminated by discarded samples");
        rst=1;#1;if(levels!==0) $fatal(1,"reset");
        $display("ALL SPECTRUM TESTS PASSED: 10 exact independent DFT windows, tones, mixture, DC, silence, saturation, gain, atomic publish and restart");
        passed=1;$finish;
    end
    initial begin #50000000;$fatal(1,"spectrum watchdog");end
endmodule
