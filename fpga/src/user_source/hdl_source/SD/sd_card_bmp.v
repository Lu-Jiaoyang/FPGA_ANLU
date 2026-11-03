module sd_card_bmp #(
    parameter integer CLK_FREQ_HZ = 100000000,
    parameter integer LONG_PRESS_MS = 1000,
    parameter integer AUTO_PLAY_MS = 3000,
    parameter integer IO_TIMEOUT_MS = 500,
    parameter integer LOAD_TIMEOUT_MS = 10000
)(
    input clk, rst, key_next, key_auto, remote_next_pulse,memory_ready,
    input quiz_mode, page_valid,
    input [1:0] auto_period,
    input [3:0] page_number,
    output page_ready,
    output reg page_done, page_failed,
    output reg page_change_toggle,
    output reg auto_play_en,
    output [3:0] state_code,
    output [7:0] error_code,
    input [15:0] bmp_width, bmp_height,
    output reg display_valid,
    output reg present_toggle,
    output wire [1:0] present_bank,
    output wire [3:0] present_page,
    output wire [10:0] present_width, present_height,
    input present_ack_toggle,
    output wire load_begin,
    input write_finish_toggle,
    output reg [1:0] write_buf_idx, disp_buf_idx,
    output write_req,
    input write_req_ack,
    output write_en,
    output [31:0] write_data,
    output SD_nCS, SD_DCLK, SD_MOSI,
    input SD_MISO
);
    localparam [63:0] AUTO_PLAY_CYCLES = (64'd1 * CLK_FREQ_HZ / 1000) * AUTO_PLAY_MS;
    localparam [63:0] LONG_PRESS_CYCLES = (64'd1 * CLK_FREQ_HZ / 1000) * LONG_PRESS_MS;
    localparam [63:0] LOAD_CYCLES = (64'd1 * CLK_FREQ_HZ / 1000) * LOAD_TIMEOUT_MS;
    localparam [63:0] MAX_AUTO_CYCLES=(64'd1*CLK_FREQ_HZ/1000)*(AUTO_PLAY_MS>15000 ? AUTO_PLAY_MS : 15000);
    localparam integer AUTO_CNT_WIDTH = MAX_AUTO_CYCLES>1 ? $clog2(MAX_AUTO_CYCLES) : 1;
    reg [1:0] period_seen;
    reg [AUTO_CNT_WIDTH-1:0] auto_limit;
    wire period_changed=period_seen!=auto_period;
    always @(posedge clk or posedge rst) begin
        if(rst) begin period_seen<=0;auto_limit<=AUTO_PLAY_CYCLES-1;end
        else begin
            period_seen<=auto_period;
            case(auto_period)
                0:auto_limit<=AUTO_PLAY_CYCLES-1;
                1:auto_limit<=(64'd1*CLK_FREQ_HZ/1000)*5000-1;
                2:auto_limit<=(64'd1*CLK_FREQ_HZ/1000)*10000-1;
                3:auto_limit<=(64'd1*CLK_FREQ_HZ/1000)*15000-1;
            endcase
        end
    end
    localparam integer LONG_CNT_WIDTH = LONG_PRESS_CYCLES>1 ? $clog2(LONG_PRESS_CYCLES) : 1;
    localparam integer LOAD_CNT_WIDTH = LOAD_CYCLES>1 ? $clog2(LOAD_CYCLES) : 1;
    wire key_next_press, key_auto_stable;
    reg key_auto_stable_d, long_press_marked;
    reg [LONG_CNT_WIDTH-1:0] long_press_cnt;
    reg [AUTO_CNT_WIDTH-1:0] auto_cnt;
    reg [LOAD_CNT_WIDTH-1:0] load_timer;
    wire key_auto_short = key_auto_stable && !key_auto_stable_d && !long_press_marked;
    wire key_auto_long = !key_auto_stable && !long_press_marked && long_press_cnt==LONG_PRESS_CYCLES-1;
    wire next_press_event = key_next_press || remote_next_pulse;
    reg scan_kicked, scan_start_pulse, load_start_pulse;
    reg next_req_pending, prev_req_pending, load_busy, direct_load;
    reg direct_pending, direct_ok;
    reg [3:0] direct_index;
    reg source_done_seen, write_done_seen, write_ack_seen, write_armed;
    reg [3:0] img_idx, load_idx;
    reg [1:0] pending_buf_idx;
    reg [11:0] bad_resources;
    reg [7:0] last_error;
    reg transport_failed;
    reg present_wait;
    (* async_reg="true" *) reg [1:0] present_ack_sync;
    reg [2:0] wrfin_tgl_sync;
    reg [1:0] wrack_sync;
    wire write_finish_pulse = wrfin_tgl_sync[2] ^ wrfin_tgl_sync[1];
    wire sd_init_done, bmp_ready, scan_done, file_done, file_error, fs_fatal;
    wire [11:0] resource_valid;
    wire [7:0] fs_error;
    wire [11:0] playable = resource_valid & ~bad_resources;
    // Only PIC01..PIC04 belong to learning mode, including keys pressed during autoplay.
    wire [11:0] learnable = playable & 12'h00f;
    wire enabling_auto = key_auto_short && !auto_play_en && learnable!=0;
    wire learning_mode = !quiz_mode;
    wire [11:0] navigation_mask = learnable;
    wire multiple_learning = (learnable & (learnable-12'd1)) != 0;
    wire next_requested = next_req_pending || next_press_event;
    // Dispatch the queued long press on the next clock, outside the wide timer comparison path.
    wire prev_requested = prev_req_pending;
    wire auto_wait_enable = !period_changed && auto_play_en && display_valid && !load_busy && multiple_learning &&
                            key_auto_stable && !key_auto_short && !next_requested && !prev_requested;
    wire auto_tick = auto_cnt==auto_limit;
    wire sd_sec_read, sd_sec_read_data_valid, sd_sec_read_end;
    wire [31:0] sd_sec_read_addr;
    wire [7:0] sd_sec_read_data;
    wire [23:0] bmp_data;
    assign write_data = {bmp_data,8'd0};
    assign present_bank=pending_buf_idx;
    assign present_page=load_idx+4'd1;
    assign load_begin=load_start_pulse;
    assign state_code = display_valid ? img_idx+4'd1 : 4'd0;
    assign error_code = last_error;
    assign page_ready = quiz_mode && memory_ready && !load_busy && !direct_pending &&
                        (transport_failed || fs_fatal || (scan_done && bmp_ready));

    function [3:0] first_index;
        input [11:0] mask;
        integer n;
        begin
            first_index=0;
            for(n=11;n>=0;n=n-1) if(mask[n]) first_index=n;
        end
    endfunction
    function [3:0] step_index;
        input [3:0] cur;
        input [11:0] mask;
        input backwards;
        integer n;
        begin
            step_index=cur;
            if(backwards) begin
                for(n=0;n<12;n=n+1) if(mask[n]) step_index=n;
                for(n=0;n<12;n=n+1) if(mask[n] && n<cur) step_index=n;
            end else begin
                for(n=11;n>=0;n=n-1) if(mask[n]) step_index=n;
                for(n=11;n>=0;n=n-1) if(mask[n] && n>cur) step_index=n;
            end
        end
    endfunction
    reg [3:0] first_available, next_from_current, prev_from_current;
    reg [3:0] navigation_page;
    reg [11:0] navigation_snapshot;
    wire navigation_ready = navigation_snapshot==navigation_mask && navigation_page==img_idx;
    // Register twelve-slot selection before request dispatch to meet the 100 MHz clock.
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            first_available<=0; next_from_current<=0; prev_from_current<=0;
            navigation_page<=0; navigation_snapshot<=0;
        end else begin
            first_available<=first_index(navigation_mask);
            next_from_current<=step_index(img_idx,navigation_mask,1'b0);
            prev_from_current<=step_index(img_idx,navigation_mask,1'b1);
            navigation_page<=img_idx; navigation_snapshot<=navigation_mask;
        end
    end
    task begin_load;
        input [3:0] idx;
        begin
            load_idx<=idx;
            pending_buf_idx<=display_valid ? {1'b0,~disp_buf_idx[0]} : 2'd0;
            write_buf_idx<=display_valid ? {1'b0,~disp_buf_idx[0]} : 2'd0;
            load_start_pulse<=1; load_busy<=1; load_timer<=0;
            source_done_seen<=0; write_done_seen<=0; write_ack_seen<=0; write_armed<=0; auto_cnt<=0;
            present_wait<=0;
        end
    endtask

    key_press_debounce #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.DEBOUNCE_MS(20)) u_key_next(
        .clk(clk),.rst(rst),.button_in(key_next),.press_pulse(key_next_press),.button_stable_out());
    key_press_debounce #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.DEBOUNCE_MS(20)) u_key_auto(
        .clk(clk),.rst(rst),.button_in(key_auto),.press_pulse(),.button_stable_out(key_auto_stable));

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            key_auto_stable_d<=1; long_press_cnt<=0; long_press_marked<=0;
        end else if(!sd_init_done || !scan_kicked) begin
            key_auto_stable_d<=1; long_press_cnt<=0; long_press_marked<=0;
        end else begin
            key_auto_stable_d<=key_auto_stable;
            if(key_auto_stable) begin long_press_cnt<=0; long_press_marked<=0; end
            else if(!long_press_marked) begin
                if(key_auto_long) long_press_marked<=1;
                else long_press_cnt<=long_press_cnt+1'b1;
            end
        end
    end

    always @(posedge clk or posedge rst) begin
        if(rst) begin
            wrfin_tgl_sync<=0; wrack_sync<=0; scan_kicked<=0; scan_start_pulse<=0;
            load_start_pulse<=0; auto_play_en<=0; auto_cnt<=0; load_timer<=0;
            next_req_pending<=0; prev_req_pending<=0; load_busy<=0;
            source_done_seen<=0; write_done_seen<=0; write_ack_seen<=0; write_armed<=0;
            img_idx<=0; load_idx<=0; pending_buf_idx<=0; write_buf_idx<=0;
            disp_buf_idx<=0; display_valid<=0; bad_resources<=0;
            last_error<=0; transport_failed<=0; direct_load<=0; page_done<=0; page_failed<=0;
            page_change_toggle<=0;
            direct_pending<=0; direct_ok<=0; direct_index<=0;
            present_toggle<=0;present_wait<=0;present_ack_sync<=0;
        end else begin
            present_ack_sync<={present_ack_sync[0],present_ack_toggle};
            wrfin_tgl_sync<={wrfin_tgl_sync[1:0],write_finish_toggle};
            wrack_sync<={wrack_sync[0],write_req_ack};
            scan_start_pulse<=0; load_start_pulse<=0; page_done<=0; page_failed<=0;
            if(!scan_kicked && !transport_failed) begin
                load_timer<=load_timer+1'b1;
                if(sd_init_done && bmp_ready) begin
                    scan_start_pulse<=1; scan_kicked<=1; load_timer<=0;
                end else if(load_timer==LOAD_CYCLES-1) begin
                    transport_failed<=1; last_error<=8'h34;
                end
            end
            if(scan_done && !display_valid && !load_busy && playable==0)
                last_error<=fs_error!=0 ? fs_error : 8'h15;
            if(auto_wait_enable) begin
                if(auto_tick) auto_cnt<=0; else auto_cnt<=auto_cnt+1'b1;
            end else auto_cnt<=0;
            if(scan_done && !transport_failed && !fs_fatal && !quiz_mode) begin
                if(next_press_event && playable!=0) next_req_pending<=1;
                if(key_auto_long && playable!=0) prev_req_pending<=1;
                if(key_auto_short && (auto_play_en || learnable!=0)) auto_play_en<=~auto_play_en;
                if(auto_play_en && learnable==0) auto_play_en<=0;
                if(memory_ready && !load_busy && bmp_ready && navigation_ready && navigation_mask!=0) begin
                    if(!display_valid) begin
                        begin_load(first_available); next_req_pending<=0; prev_req_pending<=0;
                    end else if(learning_mode && img_idx>=4) begin
                        begin_load(first_available); next_req_pending<=0; prev_req_pending<=0;
                    end else if(next_requested) begin
                        next_req_pending<=0;
                        if(next_from_current!=img_idx) begin_load(next_from_current);
                    end else if(prev_requested) begin
                        prev_req_pending<=0;
                        if(prev_from_current!=img_idx) begin_load(prev_from_current);
                    end else if(auto_wait_enable && auto_tick) begin_load(next_from_current);
                end
            end
            if(quiz_mode) begin
                auto_play_en<=0; next_req_pending<=0; prev_req_pending<=0;
                if(page_valid && page_ready) begin
                    // Register page validation before dispatch to meet the 100 MHz control clock.
                    direct_pending<=1; direct_index<=page_number-1'b1;
                    direct_ok<=page_number>=1 && page_number<=12 && playable[page_number-1'b1];
                end
                if(direct_pending) begin
                    direct_pending<=0;
                    if(transport_failed || fs_fatal) begin
                        page_failed<=1;
                    end else if(!direct_ok) begin
                        page_failed<=1; last_error<=8'h15;
                    end else begin
                        begin_load(direct_index); direct_load<=1;
                    end
                end
            end
            if(load_busy) begin
                load_timer<=load_timer+1'b1;
                if(file_done) source_done_seen<=1;
                if(write_req && wrack_sync[1]) write_ack_seen<=1;
                if(write_ack_seen && !write_req && !wrack_sync[1]) write_armed<=1;
                // Discard a delayed completion from an abandoned write until this request is acknowledged.
                if(write_armed && write_finish_pulse) write_done_seen<=1;
                if(!present_wait && !file_error && !fs_fatal && (source_done_seen || file_done) && (write_done_seen || (write_armed && write_finish_pulse))) begin
                    // Enabling autoplay cancels a question/answer frame already being loaded.
                    if(!learning_mode || load_idx<4) begin
                        present_toggle<=~present_toggle;present_wait<=1;load_timer<=0;
                    end else begin load_busy<=0;direct_load<=0;end
                end
                // Do not reuse the old framebuffer or acknowledge B until the pixel domain finishes.
                if(present_wait && present_ack_sync[1]==present_toggle) begin
                    load_busy<=0;present_wait<=0;source_done_seen<=0;write_done_seen<=0;
                    if(direct_load) begin page_done<=1;direct_load<=0;end
                    if(display_valid && img_idx!=load_idx) page_change_toggle<=~page_change_toggle;
                    img_idx<=load_idx;disp_buf_idx<=pending_buf_idx;display_valid<=1;last_error<=0;
                end
                if(file_error) begin
                    // A partial/invalid frame never becomes the displayed buffer.
                    load_busy<=0; source_done_seen<=0; write_done_seen<=0;
                    bad_resources[load_idx]<=1; last_error<=fs_error;
                    if(direct_load) begin page_failed<=1; page_done<=0; direct_load<=0; end
                    next_req_pending<=0; prev_req_pending<=0;
                end else if(load_timer==LOAD_CYCLES-1) begin
                    load_busy<=0; transport_failed<=1; last_error<=present_wait ? 8'h35 : 8'h33;
                    if(direct_load) begin page_failed<=1; page_done<=0; direct_load<=0; end
                    auto_play_en<=0; next_req_pending<=0; prev_req_pending<=0;
                end
            end
            if(fs_fatal) begin
                transport_failed<=1; last_error<=fs_error; load_busy<=0;
                if(direct_load) begin page_failed<=1; page_done<=0; direct_load<=0; end
                auto_play_en<=0; next_req_pending<=0; prev_req_pending<=0;
            end
        end
    end

    fat32_bmp_reader #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.IO_TIMEOUT_MS(IO_TIMEOUT_MS)) reader(
        .clk(clk),.rst(rst),.sd_init_done(sd_init_done),.scan_start(scan_start_pulse),
        .scan_done(scan_done),.resource_valid(resource_valid),.load_start(load_start_pulse),
        .load_index(load_idx),.ready(bmp_ready),.load_done(file_done),.load_error(file_error),
        .error_code(fs_error),.fatal_error(fs_fatal),.bmp_width(bmp_width),.bmp_height(bmp_height),
        .write_req(write_req),.write_req_ack(wrack_sync[1]),.sd_sec_read(sd_sec_read),
        .sd_sec_read_addr(sd_sec_read_addr),.sd_sec_read_data(sd_sec_read_data),
        .sd_sec_read_data_valid(sd_sec_read_data_valid),.sd_sec_read_end(sd_sec_read_end),
        .bmp_data_wr_en(write_en),.bmp_data(bmp_data),
        .source_width(present_width),.source_height(present_height));
    sd_card_top sd_card_top_m0(
        .clk(clk),.rst(rst),.SD_nCS(SD_nCS),.SD_DCLK(SD_DCLK),.SD_MOSI(SD_MOSI),.SD_MISO(SD_MISO),
        .sd_init_done(sd_init_done),.sd_sec_read(sd_sec_read),.sd_sec_read_addr(sd_sec_read_addr),
        .sd_sec_read_data(sd_sec_read_data),.sd_sec_read_data_valid(sd_sec_read_data_valid),
        .sd_sec_read_end(sd_sec_read_end),.sd_sec_write(1'b0),.sd_sec_write_addr(32'd0),
        .sd_sec_write_data(8'd0),.sd_sec_write_data_req(),.sd_sec_write_end());
endmodule

module key_press_debounce #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer DEBOUNCE_MS = 20
)(
    input  wire clk,
    input  wire rst,
    input  wire button_in,    // 默认：松开=1，按下=0
    output reg  press_pulse,
    output wire button_stable_out
);

localparam integer DEBOUNCE_CYCLES = (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;

reg button_sync0;
reg button_sync1;
reg button_stable;
reg [31:0] cnt;

// 直接引出已复位的稳定电平，不复制一套寄存器。
assign button_stable_out = button_stable;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        button_sync0  <= 1'b1;
        button_sync1  <= 1'b1;
        button_stable <= 1'b1;
        cnt           <= 32'd0;
        press_pulse   <= 1'b0;
    end else begin
        button_sync0 <= button_in;
        button_sync1 <= button_sync0;
        press_pulse  <= 1'b0;

        if (button_sync1 == button_stable) begin
            cnt <= 32'd0;
        end else begin
            if (cnt >= DEBOUNCE_CYCLES - 1) begin
                if (button_stable && !button_sync1)
                    press_pulse <= 1'b1;
                button_stable <= button_sync1;
                cnt           <= 32'd0;
            end else begin
                cnt <= cnt + 32'd1;
            end
        end
    end
end

endmodule
