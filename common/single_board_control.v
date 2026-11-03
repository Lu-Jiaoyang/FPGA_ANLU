// Both proven session machines now exchange one-cycle messages on the same clock.
module single_board_control #(
    parameter integer CLK_FREQ_HZ=100000000,
    parameter integer DEBOUNCE_MS=20,
    parameter integer LONG_HOLD_MS=1000,
    parameter integer TIMEOUT_CYCLES=CLK_FREQ_HZ*12
)(
    input wire clk,rst_n,key2_n,key3_n,key4_n,
    output wire key_next_n,key_auto_n,
    output wire [15:0] settings_bundle,
    output wire settings_toggle,
    input wire settings_ack,
    output wire quiz_mode,finished,
    output wire [7:0] score,
    output wire [1:0] effect_mode,
    output wire [3:0] correct_questions,
    output wire page_valid,
    output wire [3:0] page_number,
    input wire page_ready,page_done,page_failed,
    input wire [7:0] storage_error,
    input wire [3:0] current_page,
    output wire [7:0] seg_sel,seg_data,
    output wire pc_uart_tx,buzzer_n,
    output reg [1:0] review_caption
);
    wire start_quiz;
    picture_controls #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.DEBOUNCE_MS(DEBOUNCE_MS),.LONG_HOLD_MS(LONG_HOLD_MS)) controls(
        .clk(clk),.rst_n(rst_n),
        .key2_n(quiz_mode ? 1'b1 : key2_n),.key3_n(quiz_mode ? 1'b1 : key3_n),
        .key4_n(quiz_mode ? 1'b1 : key4_n),
        .key_next_n(key_next_n),.key_auto_n(key_auto_n),.start_quiz(start_quiz),
        .settings_bundle(settings_bundle),.settings_toggle(settings_toggle),.settings_ack(settings_ack));
    wire a_valid,b_valid;
    wire session_page_valid;
    wire [3:0] session_page_number;
    wire [7:0] a_cmd,a_seq,a_page,a_arg,b_cmd,b_seq,b_page,b_arg;
    quiz_presentation_session #(.CLK_FREQ_HZ(CLK_FREQ_HZ)) presentation_session(
        .clk(clk),.rst_n(rst_n),.start_quiz(start_quiz),
        .rx_valid(b_valid),.rx_cmd(b_cmd),.rx_seq(b_seq),.rx_page(b_page),.rx_arg(b_arg),
        .tx_valid(a_valid),.tx_ready(1'b1),.tx_cmd(a_cmd),.tx_seq(a_seq),.tx_page(a_page),.tx_arg(a_arg),
        .quiz_mode(quiz_mode),.finished(finished),.score(score),.effect_mode(effect_mode),
        .correct_questions(correct_questions),.page_valid(session_page_valid),.page_number(session_page_number),
        .page_ready(page_ready),.page_done(page_done),.page_failed(page_failed),.storage_error(storage_error));
    wire p2,p3,p4;
    // Keep debouncing during image loads: a held key must not become a new answer.
    key_debounce #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.DEBOUNCE_MS(DEBOUNCE_MS)) k2(clk,rst_n,key2_n,p2);
    key_debounce #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.DEBOUNCE_MS(DEBOUNCE_MS)) k3(clk,rst_n,key3_n,p3);
    key_debounce #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.DEBOUNCE_MS(DEBOUNCE_MS)) k4(clk,rst_n,key4_n,p4);
    wire [1:0] question_index,selected_option,correct_option;
    wire selecting,submitted,answer_correct,show_correct,answer_finished;
    wire [7:0] answer_score,comm_error;
    wire [3:0] answer_state;
    wire prev=selecting && p3, next=selecting && p2;
    wire confirm=quiz_mode && p4;
    localparam R_IDLE=0,R_SEND=1,R_WAIT=2,R_SHOW=3,R_ERROR=4,R_END=5,R_ALL=6;
    localparam integer RCW=TIMEOUT_CYCLES<2 ? 1 : $clog2(TIMEOUT_CYCLES);
    reg [2:0] review_state;
    reg [3:0] review_remaining;
    reg [1:0] review_target,review_display_index;
    reg review_show;
    reg [7:0] review_error;
    reg [RCW-1:0] review_timer;
    wire review_key_ready=finished && answer_finished && review_state!=R_SEND && review_state!=R_WAIT;
    wire review_digits=review_show || review_state==R_ERROR;
    wire [1:0] review_correct=review_display_index==0 ? 2'd1 : review_display_index==1 ? 2'd2 :
                              review_display_index==2 ? 2'd0 : 2'd3;
    // Both original session machines stay finished, so review cannot rescore or report another answer.
    assign page_valid=finished ? review_state==R_SEND : session_page_valid;
    assign page_number=finished ? 4'd9+{2'd0,review_target} : session_page_number;
    task request_review;
        input [3:0] remaining;
        begin
            review_target<=remaining[0] ? 2'd0 : remaining[1] ? 2'd1 : remaining[2] ? 2'd2 : 2'd3;
            review_remaining<=remaining;review_state<=R_SEND;review_timer<=0;review_error<=0;
            review_caption<=1;
        end
    endtask
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            review_state<=R_IDLE;review_remaining<=0;review_target<=0;review_display_index<=0;
            review_show<=0;review_error<=0;review_timer<=0;review_caption<=0;
        end else case(review_state)
            R_IDLE,R_END,R_ALL: if(review_key_ready && confirm) begin
                review_show<=0;
                if(correct_questions==4'hf) begin review_state<=R_ALL;review_caption<=2;end
                else request_review(~correct_questions);
            end
            R_SEND: begin
                if(page_ready) begin review_state<=R_WAIT;review_timer<=0;end
                else if(storage_error==8'h10 || storage_error==8'h11 || storage_error==8'h32 ||
                        storage_error==8'h33 || storage_error==8'h34) begin
                    review_state<=R_ERROR;review_error<=storage_error;
                end else if(review_timer==TIMEOUT_CYCLES-1) begin review_state<=R_ERROR;review_error<=8'h01;end
                else review_timer<=review_timer+1'b1;
            end
            R_WAIT: begin
                if(page_failed) begin review_state<=R_ERROR;review_error<=storage_error==0 ? 8'h15 : storage_error;end
                else if(page_done) begin
                    review_remaining[review_target]<=0;review_display_index<=review_target;
                    review_show<=1;review_state<=R_SHOW;review_timer<=0;
                end else if(review_timer==TIMEOUT_CYCLES-1) begin review_state<=R_ERROR;review_error<=8'h01;end
                else review_timer<=review_timer+1'b1;
            end
            R_SHOW: if(confirm) begin
                if(review_remaining!=0) request_review(review_remaining);
                else begin review_state<=R_END;review_caption<=3;review_show<=0;end
            end
            R_ERROR: if(confirm) begin review_state<=R_SEND;review_timer<=0;review_error<=0;end
            default: begin review_state<=R_IDLE;review_caption<=0;review_show<=0;end
        endcase
    end
    quiz_answer_session #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.TIMEOUT_CYCLES(TIMEOUT_CYCLES)) answer_session(
        .clk(clk),.rst_n(rst_n),.key_prev(prev),.key_next(next),.key_confirm(confirm),
        .rx_valid(a_valid),.rx_cmd(a_cmd),.rx_seq(a_seq),.rx_page(a_page),.rx_arg(a_arg),
        .tx_valid(b_valid),.tx_ready(1'b1),.tx_cmd(b_cmd),.tx_seq(b_seq),.tx_page(b_page),.tx_arg(b_arg),
        .question_index(question_index),.selected_option(selected_option),.correct_option(correct_option),
        .selecting(selecting),.submitted(submitted),.answer_correct(answer_correct),.show_correct(show_correct),
        .finished(answer_finished),.score(answer_score),.comm_error(comm_error),.state(answer_state),.click());
    quiz_pc_reporter #(.CLK_FREQ_HZ(CLK_FREQ_HZ)) reporter(
        .clk(clk),.rst_n(rst_n),.submitted(submitted),.question_index(question_index),
        .selected_option(selected_option),.correct_option(correct_option),
        .answer_correct(answer_correct),.score(answer_score),.tx(pc_uart_tx));
    key_beep #(.CLK_FREQ_HZ(CLK_FREQ_HZ)) beep(
        .clk(clk),.rst_n(rst_n),
        .trigger(prev || next || (confirm && (selecting || answer_state==7 || answer_state==12 || review_key_ready))),
        .buzzer_n(buzzer_n));
    wire [31:0] answer_digits;
    wire [7:0] answer_sel,answer_data,learning_sel,learning_data;
    quiz_answer_display #(.CLK_FREQ_HZ(CLK_FREQ_HZ)) answer_display(
        .clk(clk),.rst_n(rst_n),.selecting(selecting),.submitted(submitted),
        .answer_correct(answer_correct),.show_correct(review_show || show_correct),.finished(answer_finished && !review_digits),
        .question_index(review_show ? review_display_index : question_index),.selected_option(selected_option),
        .correct_option(review_show ? review_correct : correct_option),
        .score(answer_score),.comm_error(review_state==R_ERROR ? review_error : comm_error),
        .state(review_digits ? 4'd7 : answer_state),.digits(answer_digits),.led_status());
    seg_scan8 #(.CLK_FREQ_HZ(CLK_FREQ_HZ)) scan(clk,rst_n,answer_digits,answer_sel,answer_data);
    quiz_presentation_display #(.CLK_FREQ_HZ(CLK_FREQ_HZ)) lamps_and_learning(
        .clk(clk),.rst_n(rst_n),.quiz_mode(quiz_mode),.finished(1'b0),.key_next_n(1'b1),
        .effect_mode(effect_mode),.score(8'd0),.storage_error(storage_error),.page(current_page),
        .seg_sel(learning_sel),.seg_data(learning_data));
    reg lamp_view;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) lamp_view<=0;
        else if(review_key_ready && confirm) lamp_view<=0;
        else if(answer_state!=7 && !answer_finished) lamp_view<=0;
        else if(p2) lamp_view<=~lamp_view;
    end
    // SW6 is a physical mux, not an FPGA input. KEY2 selects lamps in result/score screens.
    wire use_answer=quiz_mode && !lamp_view;
    assign seg_sel=use_answer ? answer_sel : learning_sel;
    assign seg_data=use_answer ? answer_data : learning_data;
endmodule
