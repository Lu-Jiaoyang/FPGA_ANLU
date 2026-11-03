`timescale 1ns/1ps
module tb_audio_visualization;
    reg aclk=0,pclk=0,rst=1,background=0,win=0,page=0,vs=1;
    always #40.666 aclk=~aclk;
    always #20 pclk=~pclk;
    wire bclk,lrck,dout,valid,cue;
    wire [23:0] left_data,right_data;
    hdmi_audio_tone_i2s_64fs #(.NOTE_HOLD_FRAMES(6144),.CUE_FRAMES(240)) tone(
        .I_mclk(aclk),.I_rst(rst),.I_background(background),.I_win(win),.I_page_toggle(page),
        .I_bgm_id(2'd0),.I_quiz_mode(1'b0),.I_effect_mode(2'd0),
        .O_i2s_BCLK(bclk),.O_i2s_LRCK(lrck),.O_i2s_DOUT(dout),.O_cue_active(cue));
    I2S_receiver receiver(pclk,rst,bclk,lrck,dout,valid,left_data,right_data);
    audio_waveform_overlay overlay(pclk,rst,1'b1,vs,1'b0,24'd0,background,valid,left_data,,,,,cue);
    reg [127:0] previous_spectrum=0;
    integer spectrum_updates=0,strongest,strongest_value;
    always @(negedge pclk) if(!rst && background) begin
        if(valid && overlay.spectrum.state!=0) $fatal(1,"spectrum PCM overrun");
        if(overlay.spectrum_levels!=previous_spectrum) begin
            previous_spectrum=overlay.spectrum_levels;
            if(previous_spectrum!=0) begin
                strongest=0;strongest_value=0;
                for(integer b=0;b<16;b++) if(previous_spectrum[b*8 +: 8]>strongest_value) begin
                    strongest=b+1;strongest_value=previous_spectrum[b*8 +: 8];
                end
                if(strongest<2 || strongest>4) $fatal(1,"actual C4/D4 PCM spectrum peaks outside expected bins: %0d",strongest);
                spectrum_updates++;
            end
        end
    end
    reg [127:0] held_spectrum;
    reg passed=0;
    reg [23:0] current_left=0,previous_left=0;
    integer received=0,serial_checks=0,expected_peak=0,frame_samples=0,frames=0,magnitude;
    reg [3:0] levels_seen=0;
    reg rising_seen=0,falling_seen=0,low_seen=0,full_seen=0;
    integer old_gain=64;
    integer signed raw_sample,expected_sample;
    longint signed product;
    function automatic integer sine_ref(input integer phase);
        case(phase)
            0,8:sine_ref=0;
            1,7:sine_ref=765366;2,6:sine_ref=1414214;3,5:sine_ref=1847760;4:sine_ref=2000000;
            9,15:sine_ref=-765366;10,14:sine_ref=-1414214;11,13:sine_ref=-1847760;12:sine_ref=-2000000;
        endcase
    endfunction
    always @(posedge aclk) if(!rst && tone.O_i2s_BCLK && tone.S_bit_cnt==63 && tone.O_i2s_LRCK) begin
        raw_sample=sine_ref(tone.S_phase_acc[31:28]);expected_sample=raw_sample;
        if(!tone.playing) expected_sample=0;
        else if(tone.background_sync[1] && !tone.win_active && !tone.cue_active) begin
            product=raw_sample;product=product*tone.background_gain;
            expected_sample=(product<0 ? product-255 : product)/256;
            if(tone.background_gain>old_gain) rising_seen=1;
            if(tone.background_gain<old_gain) falling_seen=1;
            if(tone.background_gain==64) low_seen=1;
            if(tone.background_gain==256) full_seen=1;
            if(tone.background_gain<64 || tone.background_gain>256) $fatal(1,"background gain bounds");
            old_gain=tone.background_gain;
        end
        #1;if($signed(tone.S_sample_next)!==expected_sample) $fatal(1,"PCM signed envelope math");
    end
    always @(negedge lrck) if(!rst) begin
        #1;previous_left=current_left;current_left=tone.S_sample_word;
    end
    always @(negedge pclk) begin
        if(!rst && valid) begin
            received++;
            if(received>4) begin
                if(left_data!==previous_left || right_data!==previous_left) $fatal(1,"real I2S decoded sample mismatch");
                serial_checks++;
            end
            if(overlay.enable_sync[1]) begin
                magnitude=$signed(left_data);if(magnitude<0) magnitude=-magnitude;
                magnitude=magnitude/8192;if(magnitude>255) magnitude=255;
                if(magnitude>expected_peak) expected_peak=magnitude;
                frame_samples++;
            end
        end
    end
    initial begin
        repeat(10) @(negedge pclk);rst=0;
        repeat(10) @(negedge lrck);background=1;
        // Frame pacing is accelerated to 400 PCM samples so this test covers two notes quickly.
        repeat(32) begin
            wait(frame_samples>=400);
            @(negedge pclk);vs=0;
            @(posedge pclk);#1;
            if(!overlay.display_valid || overlay.display_peak!=expected_peak)
                $fatal(1,"meter must represent the actual received PCM frame peak: got%0d expected%0d",overlay.display_peak,expected_peak);
            case(overlay.quantized_peak)
                64:levels_seen[0]=1;128:levels_seen[1]=1;192:levels_seen[2]=1;255:levels_seen[3]=1;
            endcase
            frames++;expected_peak=0;frame_samples=0;
            @(negedge pclk);vs=1;
        end
        if(levels_seen!=15 || !rising_seen || !falling_seen || !low_seen || !full_seen)
            $fatal(1,"audible envelope must produce all four real meter levels %b",levels_seen);
        if(spectrum_updates<10) $fatal(1,"missing real PCM spectra");
        held_spectrum=overlay.spectrum_frame;
        page=~page;wait(tone.cue_active);
        repeat(10) @(negedge pclk);
        while(tone.cue_active) begin
            @(negedge lrck);
            @(negedge pclk);vs=0;
            repeat(4) @(negedge pclk);vs=1;
            if(overlay.spectrum_frame!==held_spectrum) $fatal(1,"cue must hold the displayed spectrum");
        end
        if(overlay.spectrum_ready) $fatal(1,"cue spectrum cannot be published");
        wait(overlay.spectrum_enable);
        if(overlay.spectrum_ready) $fatal(1,"tail must be discarded before restarting DFT");
        wait(overlay.spectrum_ready);
        @(negedge pclk);vs=0;repeat(4) @(negedge pclk);vs=1;
        if(overlay.spectrum_frame!==overlay.spectrum_levels) $fatal(1,"fresh BGM spectrum must resume");
        $display("ALL CUE SPECTRUM HOLD TESTS PASSED: real I2S cue, tail flush, fresh window and frame commit");
        background=0;repeat(10) @(negedge lrck);
        repeat(10) begin @(posedge valid);#1;if(left_data!=0) $fatal(1,"stop must silence background");end
        @(negedge pclk);vs=0;repeat(5) @(negedge pclk);
        if(overlay.enabled_frame || overlay.display_valid) $fatal(1,"stop hides visualization");
        $display("ALL AUDIO VISUALIZATION INTEGRATION TESTS PASSED: %0d real stereo PCM checks, %0d peak snapshots, all four levels, envelope, cue and stop",serial_checks,frames);
        $display("ALL REAL SPECTRUM INTEGRATION TESTS PASSED: %0d actual C4/D4 spectra, no PCM overrun",spectrum_updates);
        passed=1;$finish;
    end
    initial begin #400000000;$fatal(1,"audio integration watchdog");end
endmodule
