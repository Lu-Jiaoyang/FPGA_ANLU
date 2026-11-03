
module hdmi_audio_tone_i2s_64fs #(
    parameter [31:0] PHASE_INC = 32'd39370534,   // 兼容旧顶层，实际本版内部不用它
    parameter signed [23:0] AMP = 24'sd2000000,
    parameter integer RESULT_FRAMES = 76800,    // Answer feedback totals about 1.6s @ 48kHz
    parameter integer NOTE_HOLD_FRAMES = 24000,  // 每个音持续 0.5s @ 48kHz
    parameter integer CUE_FRAMES = 5760         // 切图提示音约120ms
)(
    input  wire I_mclk,      // 12.288MHz
    input  wire I_rst,
    input wire I_background, I_win,
    input wire [1:0] I_bgm_id,
    input wire I_page_toggle,
    input wire I_quiz_mode,
    input wire [1:0] I_effect_mode,
    output reg  O_i2s_BCLK,
    output reg  O_i2s_LRCK,
    output reg  O_i2s_DOUT,
    output wire O_cue_active
);

// do/re/mi/fa/so/la/si/do  （C4 D4 E4 F4 G4 A4 B4 C5）
// 相位增量按 48kHz 采样率计算
function [31:0] note_inc_lut;
    input [2:0] idx;
    begin
        case (idx)
            3'd0: note_inc_lut = 32'd23409862; // do  C4 261.63Hz
            3'd1: note_inc_lut = 32'd26276681; // re  D4 293.66Hz
            3'd2: note_inc_lut = 32'd29494578; // mi  E4 329.63Hz
            3'd3: note_inc_lut = 32'd31248410; // fa  F4 349.23Hz
            3'd4: note_inc_lut = 32'd35075155; // so  G4 392.00Hz
            3'd5: note_inc_lut = 32'd39370534; // la  A4 440.00Hz
            3'd6: note_inc_lut = 32'd44191930; // si  B4 493.88Hz
            default: note_inc_lut = 32'd46819716; // do  C5 523.25Hz
        endcase
    end
endfunction

// Four eight-note loops, selected by the committed learning image, not a load request.
function [2:0] background_note;
    input [1:0] track;
    input [2:0] step;
    reg [23:0] melody;
    begin
        case(track)
            0:melody={3'd7,3'd6,3'd5,3'd4,3'd3,3'd2,3'd1,3'd0};
            1:melody={3'd2,3'd4,3'd2,3'd0,3'd7,3'd4,3'd2,3'd0};
            2:melody={3'd0,3'd4,3'd2,3'd0,3'd1,3'd2,3'd4,3'd0};
            3:melody={3'd4,3'd2,3'd0,3'd2,3'd4,3'd5,3'd7,3'd4};
        endcase
        background_note=melody[step*3+:3];
    end
endfunction

// Lesson 4: a 16-point sine table, scaled at elaboration without a multiplier.
localparam signed [23:0] SINE_1 = (AMP * 64'sd382683) / 64'sd1000000;
localparam signed [23:0] SINE_2 = (AMP * 64'sd707107) / 64'sd1000000;
localparam signed [23:0] SINE_3 = (AMP * 64'sd923880) / 64'sd1000000;

function signed [23:0] sine_sample;
    input [3:0] idx;
    begin
        case (idx)
            4'd0, 4'd8:  sine_sample = 24'sd0;
            4'd1, 4'd7:  sine_sample = SINE_1;
            4'd2, 4'd6:  sine_sample = SINE_2;
            4'd3, 4'd5:  sine_sample = SINE_3;
            4'd4:        sine_sample = AMP;
            4'd9, 4'd15: sine_sample = -SINE_1;
            4'd10, 4'd14:sine_sample = -SINE_2;
            4'd11, 4'd13:sine_sample = -SINE_3;
            4'd12:       sine_sample = -AMP;
        endcase
    end
endfunction

reg  [5:0]  S_bit_cnt;
reg  [63:0] S_shift_reg;
reg  [31:0] S_phase_acc;
reg signed [23:0] S_sample_word;
reg signed [23:0] S_sample_next;
reg  [2:0]  S_note_idx;
reg [15:0]  S_note_frame_cnt;

reg [1:0] background_sync, win_sync, page_sync, quiz_sync;
reg [1:0] effect_sync_0, effect_sync_1;
reg win_seen, win_active;
reg [1:0] bgm_sync0,bgm_sync1,bgm_active;
reg background_seen,bgm_pending;
reg page_seen;
reg [1:0] victory_repeat;
reg result_active, result_correct;
localparam integer RESULT_CW=RESULT_FRAMES<2 ? 1 : $clog2(RESULT_FRAMES);
reg [RESULT_CW-1:0] result_frame_cnt;
reg [14:0] result_sample_idx;
reg [1:0] result_repeat;
wire [15:0] result_rom_addr={1'b0,result_sample_idx}+(result_correct ? 16'd0 : 16'd25600);
wire [7:0] result_pcm;
// Two 1.6-second mono recordings at 16 kHz; each sample spans three HDMI frames.
// shortcut: clips are fixed in the bitstream; use TF streaming for long or replaceable audio.
EG_LOGIC_BRAM #(.DATA_WIDTH_A(8),.DATA_WIDTH_B(8),.ADDR_WIDTH_A(16),.ADDR_WIDTH_B(16),
    .DATA_DEPTH_A(51200),.DATA_DEPTH_B(51200),.MODE("SP"),
    .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.IMPLEMENT("32K"),
    .INIT_FILE("C:/Users/lenovo/Downloads/FPGA_submission_20261031_final/science_learning_system/fpga/src/user_source/hdl_source/answer_audio.dath")) answer_rom(
    .doa(result_pcm),.dob(),.dia(8'd0),.dib(8'd0),.cea(1'b1),.ceb(1'b0),
    .ocea(1'b1),.oceb(1'b0),.clka(I_mclk),.clkb(1'b0),.wea(1'b0),.web(1'b0),
    .rsta(1'b0),.rstb(1'b0),.bea(1'b0),.beb(1'b0),.addra(result_rom_addr),.addrb(16'd0));
wire signed [23:0] result_sample={{2{result_pcm[7]}},result_pcm,14'd0};
localparam integer CUE_W=CUE_FRAMES<2 ? 1 : $clog2(CUE_FRAMES+1);
reg [CUE_W-1:0] cue_left;
wire cue_active=cue_left!=0;
assign O_cue_active=cue_active;
always @(posedge I_mclk or posedge I_rst) begin
    if(I_rst) begin
        background_sync<=0; win_sync<=0; page_sync<=0; quiz_sync<=0;
        effect_sync_0<=0; effect_sync_1<=0;bgm_sync0<=0;bgm_sync1<=0;
    end
    else begin
        background_sync<={background_sync[0],I_background}; win_sync<={win_sync[0],I_win};
        page_sync<={page_sync[0],I_page_toggle};
        quiz_sync<={quiz_sync[0],I_quiz_mode};
        bgm_sync0<=I_bgm_id;bgm_sync1<=bgm_sync0;
        effect_sync_0<=I_effect_mode; effect_sync_1<=effect_sync_0;
    end
end
function [31:0] victory_note;
    input [2:0] idx;
    begin case(idx)
        0: victory_note=32'd46819716; // C5
        1: victory_note=32'd58989156; // E5
        2: victory_note=32'd70150310; // G5
        default: victory_note=32'd93639432; // C6
    endcase end
endfunction
wire playing=background_sync[1] || win_active || result_active || cue_active;
// Priority is victory, answer feedback, page cue, then learning background.
wire [31:0] base_inc=note_inc_lut(background_note(bgm_active,S_note_idx));
// Distinct register and tempo make the first few seconds recognizable on each page.
wire [31:0] background_inc=bgm_active==1 ? base_inc<<1 : bgm_active==2 ? base_inc>>1 : base_inc;
wire [31:0] W_note_inc = win_active ? victory_note(S_note_idx) :
                             cue_active ? 32'd93639432 : background_inc;
wire [15:0] note_last=win_active ? NOTE_HOLD_FRAMES-1 :
    bgm_active==1 ? NOTE_HOLD_FRAMES/2-1 : bgm_active==2 ? NOTE_HOLD_FRAMES*2-1 : NOTE_HOLD_FRAMES-1;
wire [15:0] envelope_frame=bgm_active==1 ? S_note_frame_cnt<<1 :
    bgm_active==2 ? S_note_frame_cnt>>1 : S_note_frame_cnt;
wire background_rest=bgm_active==3 && S_note_frame_cnt>=NOTE_HOLD_FRAMES/2;
// Smoothly change the audible background gain from 1/4 to 1 and back each note.
localparam integer GAIN_HOLD=NOTE_HOLD_FRAMES/8;
localparam integer GAIN_TICKS=NOTE_HOLD_FRAMES*3/4>=384 ? NOTE_HOLD_FRAMES*3/4/384 : 1;
localparam integer GAIN_CW=$clog2(GAIN_TICKS*2+1);
wire [GAIN_CW-1:0] gain_last=bgm_active==1 ? (GAIN_TICKS>1 ? GAIN_TICKS/2-1 : 0) :
    bgm_active==2 ? GAIN_TICKS*2-1 : GAIN_TICKS-1;
reg [GAIN_CW-1:0] gain_count;
reg [8:0] background_gain;
reg gain_falling;
wire signed [23:0] tone_sample=sine_sample(S_phase_acc[31:28]);
wire signed [33:0] background_product=tone_sample*$signed({1'b0,background_gain});

always @(posedge I_mclk or posedge I_rst) begin
    if (I_rst) begin
        O_i2s_BCLK      <= 1'b0;
        O_i2s_LRCK      <= 1'b0;
        O_i2s_DOUT      <= 1'b0;
        S_bit_cnt       <= 6'd0;
        S_shift_reg     <= 64'd0;
        S_phase_acc     <= 32'd0;
        S_sample_word   <= 24'sd0;
        S_sample_next   <= 24'sd0;
        S_note_idx      <= 3'd0;
        S_note_frame_cnt<= 16'd0; win_seen<=0; win_active<=0;
        background_seen<=0;bgm_pending<=0;bgm_active<=0;
        page_seen<=0; cue_left<=0; victory_repeat<=0;
        result_active<=0; result_correct<=0; result_sample_idx<=0; result_repeat<=0; result_frame_cnt<=0;
        background_gain<=64;gain_count<=0;gain_falling<=0;
    end
    else begin
        // shortcut: legacy receiver uses 64 clocks/channel (128fs); migrate both ends together.
        O_i2s_BCLK <= ~O_i2s_BCLK;

        if (O_i2s_BCLK == 1'b1) begin
            O_i2s_DOUT  <= S_shift_reg[63];
            S_shift_reg <= {S_shift_reg[62:0], 1'b0};

            if (S_bit_cnt == 6'd63) begin
                S_bit_cnt <= 6'd0;

                if (O_i2s_LRCK == 1'b0) begin
                    // 左声道发完，右声道复用同一个样本
                    O_i2s_LRCK  <= 1'b1;
                    S_shift_reg <= {S_sample_word[23:0], 40'd0};
                end
                else begin
                    // 右声道发完，进入下一帧样本
                    O_i2s_LRCK  <= 1'b0;

                    S_phase_acc <= S_phase_acc + W_note_inc;
                    if(!playing) S_sample_next<=24'sd0;
                    else if(result_active && !win_active) S_sample_next<=result_sample;
                    else if(background_sync[1] && !win_active && !result_active && !cue_active)
                        S_sample_next<=background_rest ? 24'sd0 : background_product>>>8;
                    else S_sample_next<=sine_sample(S_phase_acc[31:28]);

                    if(!background_sync[1] || win_active || envelope_frame<GAIN_HOLD ||
                       envelope_frame>=NOTE_HOLD_FRAMES-GAIN_HOLD || S_note_frame_cnt==note_last) begin
                        background_gain<=64;gain_count<=0;gain_falling<=0;
                    end else if(gain_count==gain_last) begin
                        gain_count<=0;
                        if(!gain_falling) begin
                            if(background_gain==255) gain_falling<=1;
                            background_gain<=background_gain+1'b1;
                        end else if(background_gain>64) background_gain<=background_gain-1'b1;
                    end else gain_count<=gain_count+1'b1;

                    S_sample_word <= S_sample_next;
                    S_shift_reg   <= {S_sample_next[23:0], 40'd0};

                    // Full-size image commits are far slower than one audio sample; a toggle crosses safely.
                    page_seen<=page_sync[1];
                    background_seen<=background_sync[1];
                    // The source holds the image ID between commits. Delay one whole PCM frame
                    // after the synchronized event so all ID bits settle before capture.
                    if(background_sync[1] && (!background_seen || page_sync[1]!=page_seen)) bgm_pending<=1;
                    else bgm_pending<=0;
                    if(bgm_pending && background_sync[1]) begin
                        bgm_active<=bgm_sync1;background_gain<=64;gain_count<=0;gain_falling<=0;
                    end
                    if(win_active || (win_sync[1] && !win_seen)) begin
                        cue_left<=0; result_active<=0; result_frame_cnt<=0;
                    end else if(page_sync[1]!=page_seen) begin
                        if(quiz_sync[1] && effect_sync_1!=0) begin
                            cue_left<=0; result_active<=1; result_correct<=effect_sync_1==1;
                            result_sample_idx<=0; result_repeat<=0; result_frame_cnt<=0; S_phase_acc<=0;
                        end else begin
                            result_active<=0; result_frame_cnt<=0; cue_left<=CUE_FRAMES;
                        end
                    end else begin
                        if(cue_active) cue_left<=cue_left-1'b1;
                        if(result_active) begin
                            if(result_frame_cnt==RESULT_FRAMES-1) begin
                                result_frame_cnt<=0;
                                result_active<=0;
                            end else result_frame_cnt<=result_frame_cnt+1'b1;
                            if(result_repeat==2) begin
                                result_repeat<=0;
                                if(result_sample_idx<25599) result_sample_idx<=result_sample_idx+1'b1;
                            end else result_repeat<=result_repeat+1'b1;
                        end
                    end

                    if(win_sync[1] && !win_seen) begin
                        win_seen<=1; win_active<=1; S_note_idx<=0; S_note_frame_cnt<=0; S_phase_acc<=0; victory_repeat<=0;
                    end else if(bgm_pending && background_sync[1] && !win_active) begin
                        S_note_idx<=0;S_note_frame_cnt<=0;S_phase_acc<=0;
                    end else if(cue_active && background_sync[1] && !win_active) begin
                        S_note_frame_cnt<=0;
                    end else if(!playing) begin
                        S_note_idx<=0; S_note_frame_cnt<=0; S_phase_acc<=0;
                    end else if (S_note_frame_cnt == note_last) begin
                        S_note_frame_cnt <= 16'd0;
                        if(win_active && S_note_idx==3) begin
                            S_note_idx<=0;
                            if(victory_repeat==3) win_active<=0;
                            else victory_repeat<=victory_repeat+1'b1;
                        end
                        else if (S_note_idx == 3'd7)
                            S_note_idx <= 3'd0;
                        else
                            S_note_idx <= S_note_idx + 3'd1;
                    end
                    else begin
                        S_note_frame_cnt <= S_note_frame_cnt + 16'd1;
                    end
                end
            end
            else begin
                S_bit_cnt <= S_bit_cnt + 6'd1;
            end
        end
    end
end

endmodule
