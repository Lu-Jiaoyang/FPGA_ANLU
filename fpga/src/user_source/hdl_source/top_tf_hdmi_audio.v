
module top(
    input                       clk,
    input                       rst_n,
    input                       key1,           // 手动下一张
    input                       key3,           // physical KEY3: start quiz
    input                       key2,           // 自动播放 开/关

    output                      pc_uart_tx,
    output                      buzzer_n,
    output [3:0]                question_led,   // LED1..4: correct answers for questions 1..4

    output [7:0]                seg_sel,
    output [7:0]                seg_data,

    // HDMI TMDS
    output                      HDMI_CLK_P,
    output                      HDMI_D2_P,
    output                      HDMI_D1_P,
    output                      HDMI_D0_P,

    // HDMI DDC
    output                      HDMI_DDC_SCL,
    inout                       HDMI_DDC_SDA,

    // TF card SPI
    output                      sd_ncs,
    output                      sd_dclk,
    output                      sd_mosi,
    input                       sd_miso
);

parameter MEM_DATA_BITS = 32;
parameter ADDR_BITS     = 21;
parameter BUSRT_BITS    = 10;
parameter FRAME_PIXELS  = 24'd307200;   // 640*480
parameter BUF0_ADDR     = 24'd0;
parameter BUF1_ADDR     = FRAME_PIXELS;

wire Sdr_init_done;
wire Sdr_init_ref_vld;
wire Sdr_busy;

wire sd_card_clk;
wire ext_mem_clk;
wire ext_mem_clk_sft;
wire video_clk;
wire hdmi_5x_clk;

wire hs;
wire vs;
wire de;

wire [23:0] vout_data_raw;
wire [23:0] vout_data;
wire        display_valid;
wire frame_start,display_live,present_toggle,present_ack,load_begin;
wire [1:0] present_bank,active_bank;
wire [3:0] present_page;
wire [10:0] present_width,present_height,active_width,active_height;
wire [4:0] transition_brightness;
wire transition_wipe,transition_preview;
wire [9:0] wipe_columns;
wire effect_hs,effect_vs,effect_de;
wire osd_hs,osd_vs,osd_de;
wire [23:0] osd_rgb;
wire wave_hs,wave_vs,wave_de;
wire [23:0] wave_rgb;
wire subtitle_hs,subtitle_vs,subtitle_de;
wire [23:0] subtitle_rgb;
wire [3:0] user_brightness,user_contrast;
wire [15:0] settings_bundle;
wire [2:0] user_volume;
wire [23:0] scaled_audio_left,scaled_audio_right;
wire settings_toggle,settings_ack,key_next_routed,key_auto_routed;

wire [3:0]  state_code;
wire [7:0] storage_error;

wire        video_read_req;
wire        video_read_req_ack;
wire        video_read_en;
wire [31:0] video_read_data;

wire        sd_card_write_en;
wire [31:0] sd_card_write_data;
wire        sd_card_write_req;
wire        sd_card_write_req_ack;
wire        frame_write_finish;
reg         frame_write_toggle_mem;

wire [1:0]  write_buf_idx;
wire [1:0]  disp_buf_idx;

wire App_rd_en;
wire [ADDR_BITS-1:0] App_rd_addr;
wire Sdr_rd_en;
wire [MEM_DATA_BITS-1:0] Sdr_rd_dout;
wire App_wr_en;
wire [ADDR_BITS-1:0] App_wr_addr;
wire [MEM_DATA_BITS-1:0] App_wr_din;
wire [3:0] App_wr_dm;

wire hs_0;
wire vs_0;
wire de_0;

// HDMI 1.4b 音频发射相关
wire        audio_pll_lock;
wire        audio_mclk;
wire        audio_i2s_bclk;
wire        audio_i2s_lrck;
wire        audio_i2s_dout;
wire        audio_valid;
wire        audio_cue_active;
wire [23:0] audio_left_data;
wire [23:0] audio_right_data;
wire        acr_valid;
wire [19:0] acr_cts;
wire [19:0] acr_n;

wire        axis_s_user;
wire        axis_s_valid;
wire        axis_s_last;
wire [23:0] axis_s_data;
wire        axis_s_ready;

wire        edid_trig;
wire        edid_valid;
wire [7:0]  edid_data;

wire [9:0]  tmds_ch0_data;
wire [9:0]  tmds_ch1_data;
wire [9:0]  tmds_ch2_data;
wire [9:0]  tmds_clk_data;

// 统一复位：TF 图像链路 + HDMI 音频链路
wire rst_all;
wire sys_pll_lock,video_pll_lock;
assign rst_all = ~rst_n | ~audio_pll_lock | ~sys_pll_lock | ~video_pll_lock;
reg [1:0] pix_reset_sync,mem_reset_sync,audio_reset_sync;
always @(posedge video_clk or posedge rst_all)
    if(rst_all) pix_reset_sync<=0;else pix_reset_sync<={pix_reset_sync[0],1'b1};
always @(posedge ext_mem_clk or posedge rst_all)
    if(rst_all) mem_reset_sync<=0;else mem_reset_sync<={mem_reset_sync[0],1'b1};
always @(posedge audio_mclk or posedge rst_all)
    if(rst_all) audio_reset_sync<=0;else audio_reset_sync<={audio_reset_sync[0],1'b1};
wire rst_pix=~pix_reset_sync[1],rst_mem=~mem_reset_sync[1],rst_audio=~audio_reset_sync[1];

// 保持你原来的 TF / SDRAM / video 时钟
sys_pll sys_pll_m0(
    .refclk     (clk),
    .clk0_out   (sd_card_clk),
    .clk1_out   (ext_mem_clk),
    .clk2_out   (ext_mem_clk_sft),
    .locked     (sys_pll_lock),
    .reset      (~rst_n)
);

video_pll video_pll_m0(
    .refclk     (clk),
    .clk0_out   (video_clk),
    .clk1_out   (hdmi_5x_clk),
    .locked     (video_pll_lock),
    .reset      (~rst_n)
);

// 复用你 I2S->HDMI 工程里的 PLL，只取 12.288MHz 音频主时钟
PLL_HDMI_AUDIO u_audio_pll(
    .refclk     (clk),
    .reset      (~rst_n),
    .extlock    (audio_pll_lock),
    .clk0_out   (),
    .clk1_out   (),
    .clk2_out   (audio_mclk)
);

// mem_clk 域把 write_finish 单拍转成 toggle，供 sd_card_clk 域可靠同步
always @(posedge ext_mem_clk or posedge rst_mem) begin
    if (rst_mem)
        frame_write_toggle_mem <= 1'b0;
    else if (frame_write_finish)
        frame_write_toggle_mem <= ~frame_write_toggle_mem;
end

// ===================== TF 多图扫描与缓存（双缓冲） =====================
reg [1:0] ctrl_reset_sync;
always @(posedge sd_card_clk or posedge rst_all)
    if(rst_all) ctrl_reset_sync<=0; else ctrl_reset_sync<={ctrl_reset_sync[0],1'b1};
wire ctrl_rst_n=ctrl_reset_sync[1];
(* async_reg="true" *) reg [1:0] memory_ready_sync;
always @(posedge sd_card_clk or negedge ctrl_rst_n)
    if(!ctrl_rst_n) memory_ready_sync<=0;else memory_ready_sync<={memory_ready_sync[0],Sdr_init_done};
wire quiz_mode,quiz_finished,auto_play_en,page_valid,page_ready,page_done,page_failed;
wire page_change_toggle;
wire [7:0] quiz_score;
wire [1:0] effect_mode,review_caption;
wire [3:0] page_number;
wire [3:0] active_page;
single_board_control control(
    .clk(sd_card_clk),.rst_n(ctrl_rst_n),.key2_n(key1),.key3_n(key3),.key4_n(key2),
    .key_next_n(key_next_routed),.key_auto_n(key_auto_routed),
    .settings_bundle(settings_bundle),.settings_toggle(settings_toggle),.settings_ack(settings_ack),
    .quiz_mode(quiz_mode),.finished(quiz_finished),.score(quiz_score),.effect_mode(effect_mode),
    .correct_questions(question_led),.page_valid(page_valid),.page_number(page_number),
    .page_ready(page_ready),.page_done(page_done),.page_failed(page_failed),.storage_error(storage_error),
    .current_page(state_code),.seg_sel(seg_sel),.seg_data(seg_data),
    .pc_uart_tx(pc_uart_tx),.buzzer_n(buzzer_n),.review_caption(review_caption));

sd_card_bmp #(
    .CLK_FREQ_HZ       (100_000_000)
) sd_card_bmp_m0(
    .clk               (sd_card_clk),
    .rst               (~ctrl_rst_n),
    .key_next          (key_next_routed),
    .key_auto          (key_auto_routed),
    .remote_next_pulse (1'b0),
    .auto_period(settings_bundle[12:11]),
    .quiz_mode(quiz_mode),.page_valid(page_valid),.page_number(page_number),
    .page_ready(page_ready),.page_done(page_done),.page_failed(page_failed),.auto_play_en(auto_play_en),
    .page_change_toggle(page_change_toggle),
    .state_code        (state_code),
    .error_code        (storage_error),
    .bmp_width         (16'd640),
    .bmp_height        (16'd480),
    .display_valid     (display_valid),
    .memory_ready(memory_ready_sync[1]),
    .present_toggle(present_toggle),.present_bank(present_bank),.present_page(present_page),
    .present_width(present_width),.present_height(present_height),
    .present_ack_toggle(present_ack),.load_begin(load_begin),

    .write_finish_toggle(frame_write_toggle_mem),
    .write_buf_idx     (write_buf_idx),
    .disp_buf_idx      (disp_buf_idx),

    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data),
    .SD_nCS            (sd_ncs),
    .SD_DCLK           (sd_dclk),
    .SD_MOSI           (sd_mosi),
    .SD_MISO           (sd_miso)
);

// ===================== 原图像时序与帧缓存 =====================
reg [2:0] video_req_pipe;
(* async_reg="true" *) reg [1:0] video_ack_sync;
always @(posedge video_clk or posedge rst_pix) begin
    if(rst_pix) begin video_req_pipe<=0;video_ack_sync<=0;end
    else begin
        video_req_pipe<={video_req_pipe[1:0],video_read_req};
        video_ack_sync<={video_ack_sync[0],video_read_req_ack};
    end
end
video_timing_data video_timing_data_m0(
    .video_clk         (video_clk),
    .rst               (rst_pix),
    .read_req          (video_read_req),
    .read_req_ack      (!display_live || video_ack_sync[1]),
    .frame_start       (frame_start),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0)
);

video_delay video_delay_m0(
    .video_clk         (video_clk),
    .rst               (rst_pix),
    .read_en           (video_read_en),
    .read_data         (video_read_data[31:8]),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0),
    .hs_r              (hs),
    .vs_r              (vs),
    .de_r              (de),
    .vout_data         (vout_data_raw)
);

image_present_control presentation(
    .pix_clk(video_clk),.rst(rst_pix),.frame_start(frame_start),
    .request_toggle(present_toggle),.request_bank(present_bank),.request_page(present_page),
    .request_width(present_width),.request_height(present_height),
    .active_width(active_width),.active_height(active_height),
    .ack_toggle(present_ack),.active_bank(active_bank),.active_page(active_page),.live(display_live),
    .brightness(transition_brightness),.wipe(transition_wipe),.preview(transition_preview),
    .wipe_columns(wipe_columns));
quiz_video_effects video_effects(
    .pix_clk(video_clk),.rst(rst_pix),.hs(hs),.vs(vs),.de(de),.rgb(vout_data_raw),
    .live(display_live),.brightness(transition_brightness),.wipe(transition_wipe),
    .user_brightness(user_brightness),.user_contrast(user_contrast),
    .preview(transition_preview),.wipe_columns(wipe_columns),.storage_error(storage_error),
    .load_clk(sd_card_clk),.load_rst(!ctrl_rst_n),.load_start(load_begin),
    .pixel_write(sd_card_write_en),.load_rgb(sd_card_write_data[31:8]),
    .hs_out(effect_hs),.vs_out(effect_vs),.de_out(effect_de),.rgb_out(vout_data));
picture_osd settings_overlay(
    .clk(video_clk),.rst(rst_pix),.hs(effect_hs),.vs(effect_vs),.de(effect_de),.rgb(vout_data),
    .settings_bundle(settings_bundle),.settings_toggle(settings_toggle),.settings_ack(settings_ack),
    .source_width(active_width),.source_height(active_height),
    .bright(user_brightness),.contrast(user_contrast),.volume(user_volume),
    .hs_out(osd_hs),.vs_out(osd_vs),.de_out(osd_de),.rgb_out(osd_rgb));
audio_volume volume_control(
    .left_in(audio_left_data),.right_in(audio_right_data),.volume(user_volume),
    .left_out(scaled_audio_left),.right_out(scaled_audio_right));
audio_waveform_overlay waveform_overlay(
    .clk(video_clk),.rst(rst_pix),.hs(osd_hs),.vs(osd_vs),.de(osd_de),.rgb(osd_rgb),
    .cue_active(audio_cue_active),.enable(auto_play_en && !quiz_mode && user_volume!=0),.pcm_valid(audio_valid),.pcm_left(scaled_audio_left),
    .hs_out(wave_hs),.vs_out(wave_vs),.de_out(wave_de),.rgb_out(wave_rgb));
quiz_feedback_subtitle feedback_subtitle(
    .clk(video_clk),.rst(rst_pix),.hs(wave_hs),.vs(wave_vs),.de(wave_de),.rgb(wave_rgb),
    .active_page(active_page),.answer_correct(effect_mode==2'd1),
    .learning_autoplay(auto_play_en && !quiz_mode),.review_caption(review_caption),
    .hs_out(subtitle_hs),.vs_out(subtitle_vs),.de_out(subtitle_de),.rgb_out(subtitle_rgb));

frame_read_write #(
    .WRITE_V_FLIP     (1),
    .FRAME_WIDTH      (640),
    .FRAME_HEIGHT     (480)
) frame_read_write_m0(
    .mem_clk           (ext_mem_clk),
    .rst               (rst_mem),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),

    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout),

    .read_clk          (video_clk),
    // Delay the request so the committed bank crosses to memory before its address is latched.
    .read_req          (video_req_pipe[2] && display_live),
    .read_req_ack      (video_read_req_ack),
    .read_finish       (),
    .read_addr_0       (BUF0_ADDR),
    .read_addr_1       (BUF1_ADDR),
    .read_addr_2       (24'd0),
    .read_addr_3       (24'd0),
    .read_addr_index   (active_bank),
    .read_len          (FRAME_PIXELS),
    .read_en           (video_read_en && display_live),
    .read_data         (video_read_data),

    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_din        (App_wr_din),
    .App_wr_dm         (App_wr_dm),

    .write_clk         (sd_card_clk),
    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_finish      (frame_write_finish),
    .write_addr_0      (BUF0_ADDR),
    .write_addr_1      (BUF1_ADDR),
    .write_addr_2      (24'd0),
    .write_addr_3      (24'd0),
    .write_addr_index  (write_buf_idx),
    .write_len         (FRAME_PIXELS),
    .write_en          (sd_card_write_en),
    .write_data        (sd_card_write_data)
);

sdram U3(
    .Clk               (ext_mem_clk),
    .Clk_sft           (ext_mem_clk_sft),
    .Rst               (rst_mem),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),
    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_dm         (App_wr_dm),
    .App_wr_din        (App_wr_din),
    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout)
);

// ===================== 音频：内部 I2S 测试音 =====================
hdmi_audio_tone_i2s_64fs #(
    .PHASE_INC (32'd39370534),
    .AMP       (24'sd2000000)
) u_hdmi_audio_tone_i2s_64fs (
    .I_mclk      (audio_mclk),
    .I_rst       (rst_audio),
    .I_background(display_valid && !quiz_mode),
    .I_bgm_id(state_code[1:0]-2'd1),
    .I_win(quiz_finished && quiz_score==8'd100),
    .I_page_toggle(page_change_toggle),
    .I_quiz_mode(quiz_mode),
    .I_effect_mode(quiz_finished ? 2'd0 : effect_mode),
    .O_i2s_BCLK  (audio_i2s_bclk),
    .O_i2s_LRCK  (audio_i2s_lrck),
    .O_i2s_DOUT  (audio_i2s_dout),
    .O_cue_active(audio_cue_active)
);

I2S_receiver u_I2S_receiver(
    .I_clk              (video_clk),
    .I_rst              (rst_pix),
    .I_i2s_BCLK         (audio_i2s_bclk),
    .I_i2s_LRCK         (audio_i2s_lrck),
    .I_i2s_DOUT         (audio_i2s_dout),
    .O_audio_valid      (audio_valid),
    .O_audio_left_data  (audio_left_data),
    .O_audio_right_data (audio_right_data)
);

audio_arc_calculate #(
    .ACR_N         (6144)
) u_audio_arc_calculate (
    .I_clk         (video_clk),
    .I_rst         (rst_pix),
    .I_audio_valid (audio_valid),
    .O_acr_valid   (acr_valid),
    .O_acr_cts     (acr_cts),
    .O_acr_n       (acr_n)
);

// ===================== RGB/DE 转 AXIS 视频 =====================
video_rgb_to_axis_640x480 u_video_rgb_to_axis_640x480(
    .I_clk         (video_clk),
    .I_rst         (rst_pix),
    .I_vs          (subtitle_vs),
    .I_de          (subtitle_de),
    .I_rgb         (subtitle_rgb),
    .O_video_user  (axis_s_user),
    .O_video_valid (axis_s_valid),
    .O_video_last  (axis_s_last),
    .O_video_data  (axis_s_data)
);

// 上电后自动打一拍，触发一次 EDID 读取
startup_pulse #(
    .CNT_MAX(20'd100000)
) u_startup_pulse (
    .I_clk   (video_clk),
    .I_rst   (rst_pix),
    .O_pulse (edid_trig)
);

// ===================== 带音频的 HDMI 1.4b 发射 =====================
hdmi_1_4b_transmitter_core_wrapper #(
    .DEVICE                 ( "EG"       ),
    .HTOTAL                 ( 800        ),
    .HSA                    ( 96         ),
    .HFP                    ( 16         ),
    .HBP                    ( 48         ),
    .HACTIVE                ( 640        ),
    .VTOTAL                 ( 525        ),
    .VSA                    ( 2          ),
    .VFP                    ( 10         ),
    .VBP                    ( 33         ),
    .VACTIVE                ( 480        ),
    .VIDEO_VIC              ( 1          ),
    .VIDEO_TPG              ( "Disable"  ),
    .VIDEO_FORMAT           ( "RGB"      ),
    .AUDIO_SAMPLE_RATE      ( "48K"      ),
    .IIC_SCL_DIV            ( 250        )
) u_hdmi_1_4b_transmitter_core_wrapper(
    .I_pixel_clk        (video_clk),
    .I_rst              (rst_pix),
    .I_edid_read_trig   (edid_trig),
    .O_edid_read_valid  (edid_valid),
    .O_edid_read_data   (edid_data),

    .I_axis_s_user      (axis_s_user),
    .I_axis_s_valid     (axis_s_valid),
    .I_axis_s_last      (axis_s_last),
    .I_axis_s_data      (axis_s_data),
    .O_axis_s_ready     (axis_s_ready),

    .I_audio_valid      (audio_valid),
    .I_audio_left_data  (scaled_audio_left),
    .I_audio_right_data (scaled_audio_right),
    .I_acr_valid        (acr_valid),
    .I_acr_cts          (acr_cts),
    .I_acr_n            (acr_n),

    .O_video_locked     (),
    .O_ddc_scl          (HDMI_DDC_SCL),
    .IO_ddc_sda         (HDMI_DDC_SDA),

    .O_ch0_tmds_data    (tmds_ch0_data),
    .O_ch1_tmds_data    (tmds_ch1_data),
    .O_ch2_tmds_data    (tmds_ch2_data),
    .O_clk_tmds_data    (tmds_clk_data)
);

hdmi_phy_wrapper #(
    .DEVICE ( "EG" )
) u_hdmi2phy_wrapper(
    .I_pixel_clk        (video_clk),
    .I_serial_clk       (hdmi_5x_clk),
    .I_rst              (rst_pix),
    .I_tmds_channel_0   (tmds_ch0_data),
    .I_tmds_channel_1   (tmds_ch1_data),
    .I_tmds_channel_2   (tmds_ch2_data),
    .I_tmds_channel_clk (tmds_clk_data),
    .O_tmds_ch0_p       (HDMI_D0_P),
    .O_tmds_ch1_p       (HDMI_D1_P),
    .O_tmds_ch2_p       (HDMI_D2_P),
    .O_tmds_clk_p       (HDMI_CLK_P)
);

endmodule
