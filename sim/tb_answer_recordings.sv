`timescale 1ns/1ps
module tb_answer_recordings;
    reg clk=0,pclk=0,rst=1,page=0;
    reg [1:0] effect=0;
    always #40.666 clk=~clk;
    always #20 pclk=~pclk;
    wire bclk,lrck,dout,valid;
    wire [23:0] left_data,right_data;
    hdmi_audio_tone_i2s_64fs dut(clk,rst,1'b0,1'b0,2'd0,page,1'b1,effect,bclk,lrck,dout,);
    I2S_receiver receiver(pclk,rst,bclk,lrck,dout,valid,left_data,right_data);
    reg [7:0] samples[0:51199];
    reg [23:0] previous_word=0,current_word=0;
    reg passed=0;
    integer frame_index=0,base=0,checks=0,received=0,serial_checks=0,starts=0;
    integer expected_pcm;
    always @(posedge rst) begin
        received=0;previous_word=0;current_word=0;
    end
    always @(posedge dut.result_active) begin
        frame_index=0;starts=starts+1;
        base=(effect==1 ? 0 : 25600);
    end
    always @(posedge clk) if(!rst && dut.O_i2s_BCLK && dut.S_bit_cnt==63 && dut.O_i2s_LRCK) begin
        if(dut.result_active) begin
            if(dut.result_rom_addr!==base+frame_index/3) $fatal(1,"recording address/rate mismatch");
            expected_pcm=$signed(samples[base+frame_index/3]);
            expected_pcm=expected_pcm*16384;
            frame_index=frame_index+1;checks=checks+1;
            #1;
            if($signed(dut.S_sample_next)!==expected_pcm) $fatal(1,"recorded PCM mismatch at frame %0d",frame_index-1);
        end
    end
    always @(negedge lrck) if(!rst) begin
        #1;previous_word=current_word;current_word=dut.S_sample_word;
    end
    always @(negedge pclk) if(!rst && valid) begin
        received=received+1;
        if(received>4) begin
            if(left_data!==previous_word || right_data!==previous_word)
                $fatal(1,"recorded stereo I2S mismatch: left=%h right=%h expected=%h",left_data,right_data,previous_word);
            serial_checks=serial_checks+1;
        end
    end
    task play_full(input [1:0] mode);
        begin
            @(negedge clk);effect=mode;page=~page;
            wait(dut.result_active);wait(!dut.result_active);
            #2;if(frame_index!=76800) $fatal(1,"recording must play exactly 1.6s at 48kHz");
            repeat(10) @(negedge lrck);
            if(dut.S_sample_word!==0) $fatal(1,"recording must return to silence");
            repeat(50) @(negedge lrck);
        end
    endtask
    initial begin
        $readmemh("fpga/src/user_source/hdl_source/answer_audio.dath",samples);
        repeat(10) @(negedge clk);rst=0;
        repeat(10) @(negedge lrck);
        play_full(1);play_full(2);
        if(starts!=2 || checks!=153600 || serial_checks<153600) $fatal(1,"incomplete recording coverage");
        // A new question interrupts a clip, with no delayed replay of the result.
        @(negedge clk);effect=2;page=~page;
        wait(dut.result_active);repeat(100) @(negedge lrck);
        @(negedge clk);effect=0;page=~page;
        wait(dut.cue_active);
        if(dut.result_active) $fatal(1,"question did not cancel recording");
        wait(!dut.cue_active);repeat(10) @(negedge lrck);
        if(dut.S_sample_word!==0 || starts!=3) $fatal(1,"late result replay");
        // Reset during a clip must discard the old cursor and pending audio.
        @(negedge clk);effect=1;page=~page;wait(dut.result_active);
        repeat(25) @(negedge lrck);
        @(negedge clk);rst=1;page=0;effect=0;
        repeat(10) @(negedge clk);rst=0;
        repeat(10) @(negedge lrck);
        if(dut.result_active || dut.S_sample_word!==0) $fatal(1,"reset did not silence recording");
        $display("ALL ANSWER RECORDING TESTS PASSED: 153600 exact PCM frames, stereo I2S, 1.6s each, no repeat, page interruption and reset");
        passed=1;$finish;
    end
    initial begin #4000000000;$fatal(1,"recordings watchdog");end
endmodule
