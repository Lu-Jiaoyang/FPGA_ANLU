// Final LEDs are the default; KEY2 selects score scanning, with SW6 switched manually to match.
module quiz_presentation_display #(parameter integer CLK_FREQ_HZ=100000000)(
    input wire clk,rst_n,quiz_mode,finished,key_next_n,
    input wire [1:0] effect_mode,
    input wire [7:0] score,storage_error,
    input wire [3:0] page,
    output wire [7:0] seg_sel,seg_data
);
    localparam integer HALF=CLK_FREQ_HZ/2, STEP=CLK_FREQ_HZ/5, RAMP=CLK_FREQ_HZ/256;
    reg [$clog2(HALF)-1:0] blink_count;
    reg visible,was_finished;
    reg [$clog2(STEP)-1:0] chase_count;
    reg [2:0] chase_index;
    reg [$clog2(RAMP)-1:0] ramp_count;
    reg [7:0] brightness,pwm;
    reg falling;
    reg [1:0] old_effect;
    reg score_view;
    wire toggle_view;
    key_debounce #(.CLK_FREQ_HZ(CLK_FREQ_HZ)) view_key(clk,rst_n,key_next_n,toggle_view);
    wire [11:0] score_value;
    score_digits u_score(score,score_value);
    reg [31:0] digits;
    wire [7:0] digit_sel,digit_data;
    wire [7:0] lamps=effect_mode==1 ? (8'b1 << chase_index) :
                      effect_mode==2 ? {8{pwm<brightness}} : 8'd0;
    wire use_lamps=quiz_mode && (!finished || !score_view);
    assign seg_data=use_lamps ? lamps : digit_data;
    assign seg_sel=use_lamps ? 8'd0 : digit_sel;
    seg_scan8 #(.CLK_FREQ_HZ(CLK_FREQ_HZ)) scan(clk,rst_n,digits,digit_sel,digit_data);
    always @* begin
        digits=32'hffffffff;
        if(finished) begin if(visible) digits[11:0]=score_value; end
        else if(storage_error!=0) begin
            digits[3:0]=4'he; digits[7:4]=storage_error[7:4]; digits[11:8]=storage_error[3:0];
        end else digits[3:0]=page;
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            blink_count<=0; visible<=1; was_finished<=0; score_view<=0;
            chase_count<=0; chase_index<=0; ramp_count<=0; brightness<=0; pwm<=0; falling<=0; old_effect<=0;
        end else begin
            was_finished<=finished; old_effect<=effect_mode; pwm<=pwm+1'b1;
            if(!finished || !was_finished) score_view<=0;
            else if(toggle_view) score_view<=~score_view;
            if(!finished || !was_finished || (toggle_view && !score_view)) begin blink_count<=0; visible<=1; end
            else if(blink_count==HALF-1) begin blink_count<=0; visible<=~visible; end
            else blink_count<=blink_count+1'b1;
            if(effect_mode!=old_effect || effect_mode==0) begin
                chase_count<=0; chase_index<=0; ramp_count<=0; brightness<=0; falling<=0;
            end else begin
                if(chase_count==STEP-1) begin chase_count<=0; chase_index<=chase_index+1'b1; end
                else chase_count<=chase_count+1'b1;
                if(ramp_count==RAMP-1) begin
                    ramp_count<=0;
                    if(!falling) begin
                        if(brightness==254) falling<=1;
                        brightness<=brightness+1'b1;
                    end else begin
                        if(brightness==1) falling<=0;
                        brightness<=brightness-1'b1;
                    end
                end else ramp_count<=ramp_count+1'b1;
            end
        end
    end
endmodule
