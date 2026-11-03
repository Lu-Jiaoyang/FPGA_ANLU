// Commit real PCM frame peaks before drawing mirrored bars in the learning-image margins.
module audio_waveform_overlay(
    input wire clk,rst,
    input wire hs,vs,de,
    input wire [23:0] rgb,
    input wire enable,
    input wire pcm_valid,
    input wire [23:0] pcm_left,
    output reg hs_out,vs_out,de_out,
    output reg [23:0] rgb_out,
    input wire cue_active
);
    // Both 80-pixel side margins are empty; leave the picture, captions and parameter OSD clear.
    localparam [8:0] BAR_Y=240,BOTTOM_Y=368;
    (* async_reg="true" *) reg [1:0] enable_sync;
    reg enabled_frame,vs_d,de_d;
    (* async_reg="true" *) reg [1:0] cue_sync;
    reg [2:0] cue_tail;
    wire spectrum_enable=enable_sync[1] && !cue_sync[1] && cue_tail==0;
    wire spectrum_ready;
    // I2S serialization/decoding trails the cue flag; discard four received tail samples.
    always @(posedge clk or posedge rst) begin
        if(rst) begin cue_sync<=0;cue_tail<=0;end
        else begin
            cue_sync<={cue_sync[0],cue_active};
            if(cue_sync[1]) cue_tail<=4;
            else if(pcm_valid && cue_tail!=0) cue_tail<=cue_tail-1'b1;
        end
    end
    reg [9:0] x;
    reg [8:0] y;
    reg display_valid;
    reg [5:0] capture_count;
    reg [3:0] decimate_count;
    reg [7:0] capture_peak,display_peak;
    reg [7:0] peak_history [0:3];
    integer n;

    wire frame_start=vs_d && !vs;
    wire [9:0] px=de_d ? x : 10'd0;
    wire [23:0] pcm_abs=pcm_left[23] ? (~pcm_left+24'd1) : pcm_left;
    // shortcut: fixed display gain for the current +/-2,000,000 PCM tone; recalibrate for other audio sources.
    wire [7:0] magnitude=|pcm_abs[23:21] ? 8'd255 : pcm_abs[20:13];
    wire [9:0] local_x=px<80 ? px-10'd8 : 10'd631-px;
    wire [8:0] local_y=y-BAR_Y;
    wire [7:0] selected_peak=peak_history[local_y[6:5]];
    wire [7:0] quantized_peak=display_peak==0 ? 8'd0 :
        display_peak<64 ? 8'd64 : display_peak<128 ? 8'd128 : display_peak<192 ? 8'd192 : 8'd255;
    wire [6:0] bar_length=selected_peak==0 ? 7'd0 : selected_peak<64 ? 7'd16 :
        selected_peak<128 ? 7'd32 : selected_peak<192 ? 7'd48 : 7'd64;
    wire bar_pixel=display_valid && ((px>=8 && px<72) || (px>=568 && px<632)) &&
        y>=BAR_Y && y<BOTTOM_Y && local_y[4:0]<24 && local_y[2:0]<6 &&
        local_x[2:0]<6 && local_x<{3'd0,bar_length};
    wire [23:0] bar_color=local_y[6:5]==0 ? 24'h168aff : local_y[6:5]==1 ? 24'h18d9ff :
        local_y[6:5]==2 ? 24'h20ffb0 : 24'hffc040;

    wire [127:0] spectrum_levels;
    reg [127:0] spectrum_frame;
    audio_spectrum16 spectrum(clk,rst,spectrum_enable,pcm_valid,pcm_left,spectrum_levels,spectrum_ready);
    // Eight ascending frequency bins per margin, below the inward peak blocks.
    wire [9:0] spectrum_x=px<80 ? px-10'd8 : px-10'd568;
    wire [3:0] spectrum_bin={px>=568,spectrum_x[5:3]};
    wire [7:0] spectrum_level=spectrum_frame[spectrum_bin*8 +: 8];
    wire [2:0] spectrum_height=spectrum_level[7:5];
    wire [8:0] spectrum_y=9'd439-y;
    // Preserve the validated analysis topology; only its final pixel output is disabled.
    (* keep="true", dont_touch="true" *) wire spectrum_pixel=(px>=568 && px<632) &&
        y>=384 && y<440 && spectrum_x[2:0]<6 && spectrum_y[2:0]<6 &&
        spectrum_y[5:3]<spectrum_height;
    wire [23:0] spectrum_color=px<80 ? 24'h20ffb0 : 24'h18d9ff;

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            enable_sync<=0;enabled_frame<=0;vs_d<=0;de_d<=0;x<=0;y<=0;
            display_valid<=0;spectrum_frame<=0;
            for(n=0;n<4;n=n+1) peak_history[n]<=0;
            capture_count<=0;decimate_count<=0;capture_peak<=0;display_peak<=0;
            hs_out<=0;vs_out<=0;de_out<=0;rgb_out<=0;
        end else begin
            enable_sync<={enable_sync[0],enable};vs_d<=vs;de_d<=de;
            if(frame_start) y<=0;
            else if(de_d && !de) y<=y+1'b1;
            if(de) x<=px+1'b1;else x<=0;
            hs_out<=hs;vs_out<=vs;de_out<=de;
            rgb_out<=!de ? 24'd0 : !enabled_frame ? rgb :
                bar_pixel ? bar_color : rgb;

            if(frame_start) begin
                if(!enable_sync[1]) spectrum_frame<=0;
                else if(spectrum_enable && spectrum_ready) spectrum_frame<=spectrum_levels;
                enabled_frame<=enable_sync[1];
                display_valid<=enable_sync[1] && capture_count==32;
                display_peak<=enable_sync[1] && capture_count==32 ? capture_peak : 8'd0;
                if(enable_sync[1] && capture_count==32) begin
                    for(n=0;n<3;n=n+1) peak_history[n]<=peak_history[n+1];
                    peak_history[3]<=capture_peak;
                end else begin
                    for(n=0;n<4;n=n+1) peak_history[n]<=0;
                end
                capture_count<=0;decimate_count<=0;capture_peak<=0;
            end else if(!enable_sync[1]) begin
                capture_count<=0;decimate_count<=0;capture_peak<=0;
            end else if(pcm_valid) begin
                // Each bar is a recent frame peak, not a frequency band; meter every PCM sample.
                if(magnitude>capture_peak) capture_peak<=magnitude;
                if(capture_count<32) begin
                    if(decimate_count==0) begin
                        capture_count<=capture_count+1'b1;decimate_count<=11;
                    end else decimate_count<=decimate_count-1'b1;
                end
            end
        end
    end
endmodule
