`timescale 1ns/1ps
module tb_learning_media;
    reg clk=0,rst=1;
    always #5 clk=~clk;
    reg [1:0] period=0,track=0;
    reg background=0,page=0,quiz=0,win=0;
    wire bclk,lrck,dout;
    reg passed=0;
    sd_card_bmp #(.CLK_FREQ_HZ(1000)) storage(
        .clk(clk),.rst(rst),.auto_period(period),.key_next(1'b1),.key_auto(1'b1),
        .remote_next_pulse(1'b0),.memory_ready(1'b1),.quiz_mode(1'b0),.page_valid(1'b0),
        .page_number(4'd0),.bmp_width(16'd640),.bmp_height(16'd480),
        .present_ack_toggle(1'b0),.write_finish_toggle(1'b0),.write_req_ack(1'b0),.SD_MISO(1'b1));
    hdmi_audio_tone_i2s_64fs #(.NOTE_HOLD_FRAMES(32),.CUE_FRAMES(4)) music(
        .I_mclk(clk),.I_rst(rst),.I_background(background),.I_win(win),.I_bgm_id(track),
        .I_page_toggle(page),.I_quiz_mode(quiz),.I_effect_mode(2'd0),
        .O_i2s_BCLK(bclk),.O_i2s_LRCK(lrck),.O_i2s_DOUT(dout));
    reg [15:0] bundle=16'h8044;
    reg toggle=0,vs=1,de=0;
    wire [23:0] osd_rgb;
    wire ack;
    picture_osd osd(.clk(clk),.rst(rst),.hs(1'b1),.vs(vs),.de(de),.rgb(24'h123456),
        .rgb_out(osd_rgb),.settings_bundle(bundle),.settings_toggle(toggle),.settings_ack(ack),
        .source_width(11'd640),.source_height(11'd480));
    task cycles(input integer n);repeat(n) @(negedge clk);endtask
    task check(input bit ok,input string msg);if(!ok) $fatal(1,"learning media: %s",msg);endtask
    task sample;@(negedge lrck);#1;endtask
    task raster(input bit menu_on,input string filename);
        integer fd,highlighted;
        reg [23:0] expected_pixel;
        begin
            fd=$fopen(filename,"w");highlighted=0;
            vs=0;cycles(2);vs=1;cycles(2);
            for(integer yy=0;yy<480;yy++) begin
                for(integer xx=0;xx<640;xx++) begin
                    @(negedge clk);de=1;
                    @(posedge clk);#1;
                    if(menu_on ? (xx<116 || xx>=524 || yy<112 || yy>=368) :
                                 (xx<8 || xx>=136 || yy<8 || yy>=88))
                        check(osd_rgb==24'h123456,"OSD must not cover pixels outside its panel");
                    if(osd_rgb==24'hffe060) begin
                        check(menu_on && yy>=320 && yy<352,"only volume row is selected");
                        highlighted++;
                    end
                    $fdisplay(fd,"%06x",osd_rgb);
                end
                @(negedge clk);de=0;cycles(2);
            end
            check(menu_on ? highlighted>0 : highlighted==0,"VOL highlight visibility");
            $fclose(fd);
        end
    endtask
    integer limits[4]='{3000,5000,10000,15000};
    integer notes[4][8]='{'{0,1,2,3,4,5,6,7},'{0,2,4,7,0,2,4,2},'{0,4,2,1,0,2,4,0},'{4,7,5,4,2,0,2,4}};
    integer incs[8]='{23409862,26276681,29494578,31248410,35075155,39370534,44191930,46819716};
    reg [31:0] previous_phase;
    integer note_steps,track_checks=0,note_frames,expected_inc;
    integer durations[4]='{32,16,64,32};
    initial begin
        cycles(5);rst=0;
        force storage.scan_kicked=1;force storage.scan_done=0;
        force storage.auto_play_en=1;force storage.display_valid=1;
        force storage.load_busy=0;force storage.resource_valid=12'h00f;
        force storage.key_auto_stable=1;force storage.key_auto_stable_d=1;
        force storage.next_req_pending=0;force storage.prev_req_pending=0;
        for(integer p=0;p<4;p++) begin
            force storage.auto_play_en=0;cycles(3);period=p;cycles(3);
            check(storage.auto_limit==limits[p]-1,"period hardware limit");
            force storage.auto_play_en=1;
            cycles(limits[p]-1);check(storage.auto_cnt==limits[p]-1 && storage.auto_tick,"exact dwell threshold");
            cycles(1);check(storage.auto_cnt==0,"timer restarts at expiry");
        end
        cycles(10);period=0;cycles(1);check(storage.auto_cnt==0,"changing long period to short restarts timer");
        cycles(10);force storage.load_busy=1;cycles(20);check(storage.auto_cnt==0,"loading does not consume dwell");
        force storage.load_busy=0;cycles(10);force storage.auto_play_en=0;cycles(20);
        check(storage.auto_cnt==0,"stopped autoplay does not count");
        // Menu packet is held until the next video frame, with all fields committed together.
        bundle={3'd4,2'd3,1'b1,2'd2,4'd5,4'd6};toggle=1;cycles(5);
        check(osd.active==16'h8044 && !ack,"OSD must wait for frame");
        vs=0;cycles(2);vs=1;cycles(2);
        check(osd.active==bundle && ack,"atomic menu snapshot");
        check(osd.value_char(3,0,5,6,3,4,0,0)=="1" && osd.value_char(3,1,5,6,3,4,0,0)=="5","OSD interval digits");
        for(integer v=0;v<=4;v++) begin
            bundle={v[2:0],2'd3,1'b1,2'd3,4'd5,4'd6};toggle=~toggle;cycles(5);
            check(osd.volume!=v || v==4,"volume waits for frame commit");
            vs=0;cycles(2);vs=1;cycles(2);
            check(osd.volume==v && ack==toggle,"volume frame-atomic commit");
            check(osd.value_char(4,0,5,6,3,v,0,0)==48+(v*25)/100 &&
                  osd.value_char(4,1,5,6,3,v,0,0)==48+((v*25)/10)%10 &&
                  osd.value_char(4,2,5,6,3,v,0,0)==48+(v*25)%10,"volume percentage digits");
        end
        raster(1,"sim/period_menu.hex");
        bundle={3'd4,2'd3,1'b0,2'd2,4'd5,4'd6};toggle=~toggle;cycles(5);
        raster(0,"sim/period_menu_closed.hex");
        $display("ALL VOLUME OSD TESTS PASSED: frame commit, five exact percentages, highlighted VOL and unchanged pixels outside panel");
        // Each page starts its own melody. Changes to the bus without a commit do not switch music.
        for(integer t=0;t<4;t++) begin
            @(negedge clk);track=t;background=1;if(t!=0) page=~page;
            wait(music.bgm_pending);sample();
            check(music.bgm_active==t && music.S_note_idx==0,"committed page resets melody");
            if(t!=0) begin wait(!music.cue_active);sample();end
            note_steps=0;
            while(note_steps<8) begin
                expected_inc=incs[notes[t][note_steps]];
                if(t==1) expected_inc=expected_inc*2;
                if(t==2) expected_inc=expected_inc/2;
                check(music.W_note_inc==expected_inc,"page-specific pitch and octave");
                note_frames=music.S_note_frame_cnt;
                while(music.S_note_idx==note_steps) begin
                    check(music.background_rest==(t==3 && music.S_note_frame_cnt>=16),"only fourth melody has half-beat rests");
                    previous_phase=music.S_phase_acc;sample();note_frames++;
                    check(music.S_phase_acc-previous_phase==expected_inc,"phase oscillator uses selected pitch");
                    if(t==3 && note_frames>16) check(music.S_sample_next==0,"staccato rests are silent PCM");
                end
                check(note_frames==durations[t],"each melody has exact distinct tempo");
                track_checks++;note_steps++;
            end
            check(music.S_note_idx==0,"melody loops after eight notes");
        end
        track=0;repeat(5) sample();check(music.bgm_active==3,"uncommitted ID must not change music");
        background=0;quiz=1;repeat(8) sample();check(music.S_sample_word==0,"quiz stops learning BGM");
        // Review uses quiz mode with neutral effect: page cue only, never another answer recording.
        page=~page;wait(music.cue_active);#1;
        check(!music.result_active,"review page must not replay wrong-answer recording");
        repeat(10) sample();check(!music.cue_active && music.S_sample_word==0,"review cue ends without BGM or answer feedback");
        win=1;wait(music.win_active);#1;
        for(integer n=0;n<16;n++) begin
            check(music.W_note_inc==(n%4==0 ? 46819716 : n%4==1 ? 58989156 : n%4==2 ? 70150310 : 93639432),"victory overrides page BGM");
            repeat(32) sample();
        end
        check(!music.win_active,"victory stops after four repeats");
        repeat(10) sample();check(!music.win_active && music.S_sample_word==0,"victory cannot retrigger while win remains high");
        rst=1;cycles(3);check(music.bgm_active==0 && storage.auto_cnt==0,"reset state");
        $display("ALL LEARNING MEDIA TESTS PASSED: four exact dwell periods, change/load/stop, atomic OSD/pixels, 32 melody notes and victory priority");
        passed=1;$finish;
    end
    initial begin #60000000;$fatal(1,"learning media watchdog");end
endmodule
