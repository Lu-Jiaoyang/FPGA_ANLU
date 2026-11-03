// A replies only after the requested image has passed validation and memory write completion.
module quiz_presentation_session #(
    parameter integer CLK_FREQ_HZ=100000000,
    parameter integer RETRY_CYCLES=CLK_FREQ_HZ
)(
    input wire clk,rst_n,start_quiz,
    input wire rx_valid,tx_ready,
    input wire [7:0] rx_cmd,rx_seq,rx_page,rx_arg,
    output wire tx_valid,
    output wire [7:0] tx_cmd,tx_seq,tx_page,tx_arg,
    output reg quiz_mode,finished,
    output reg [7:0] score,
    output reg [1:0] effect_mode,
    output reg [3:0] correct_questions,
    output wire page_valid,
    output wire [3:0] page_number,
    input wire page_ready,page_done,page_failed,
    input wire [7:0] storage_error
);
    localparam LEARN=0,START_SEND=1,START_WAIT=2,ACTIVE=3,LOAD_SEND=4,LOAD_WAIT=5,REPLY=6;
    reg [2:0] state;
    localparam integer CW=RETRY_CYCLES<2 ? 1 : $clog2(RETRY_CYCLES);
    reg [CW-1:0] timer;
    reg [7:0] session_counter,session,expected_seq;
    reg [7:0] saved_cmd,saved_seq,saved_page,saved_arg,reply_cmd,reply_arg;
    reg [7:0] last_cmd,last_seq,last_page,last_arg;
    reg cache_valid;
    wire is_question=rx_cmd==8'h20 && rx_page>=5 && rx_page<=8 && rx_arg==0;
    wire is_answer=rx_cmd==8'h21 && rx_page>=9 && rx_page<=12 && rx_arg<8;
    wire is_finish=rx_cmd==8'h22 && rx_page==0 &&
        (rx_arg==0 || rx_arg==25 || rx_arg==50 || rx_arg==75 || rx_arg==100);
    wire duplicate=cache_valid && rx_cmd==last_cmd && rx_seq==last_seq && rx_page==last_page && rx_arg==last_arg;
    assign page_valid=state==LOAD_SEND;
    assign page_number=saved_page[3:0];
    assign tx_valid=state==START_SEND || state==REPLY;
    assign tx_cmd=state==START_SEND ? 8'h10 : reply_cmd;
    assign tx_seq=state==START_SEND ? session : saved_seq;
    assign tx_page=state==START_SEND ? 8'd0 : saved_page;
    assign tx_arg=state==START_SEND ? 8'd0 : reply_arg;
    task success;
        begin
            reply_cmd<=saved_cmd|8'h80; reply_arg<=0; state<=REPLY;
            last_cmd<=saved_cmd; last_seq<=saved_seq; last_page<=saved_page; last_arg<=saved_arg;
            cache_valid<=1; expected_seq<=expected_seq+1'b1;
        end
    endtask
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=LEARN; quiz_mode<=0; finished<=0; score<=0; effect_mode<=0; correct_questions<=0;
            session_counter<=0; session<=0; expected_seq<=0; timer<=0; cache_valid<=0;
            saved_cmd<=0; saved_seq<=0; saved_page<=0; saved_arg<=0; reply_cmd<=0; reply_arg<=0;
            last_cmd<=0; last_seq<=0; last_page<=0; last_arg<=0;
        end else begin
            session_counter<=session_counter+1'b1;
            case(state)
                LEARN: if(start_quiz) begin
                    session<=session_counter; expected_seq<=session_counter+8'd1;
                    quiz_mode<=1; cache_valid<=0; state<=START_SEND; timer<=0; correct_questions<=0;
                end
                START_SEND: if(tx_ready) begin state<=START_WAIT; timer<=0; end
                START_WAIT,ACTIVE: begin
                    if(state==START_WAIT) begin
                        if(timer==RETRY_CYCLES-1) begin state<=START_SEND; timer<=0; end
                        else timer<=timer+1'b1;
                    end
                    if(rx_valid && (rx_cmd==8'h20 || rx_cmd==8'h21 || rx_cmd==8'h22)) begin
                        if(duplicate) begin
                            saved_cmd<=rx_cmd; saved_seq<=rx_seq; saved_page<=rx_page; saved_arg<=rx_arg;
                            reply_cmd<=rx_cmd|8'h80; reply_arg<=0; state<=REPLY;
                        end else if(rx_seq==expected_seq && !finished) begin
                            saved_cmd<=rx_cmd; saved_seq<=rx_seq; saved_page<=rx_page; saved_arg<=rx_arg;
                            if(is_question || is_answer) begin
                                state<=LOAD_SEND;
                                effect_mode<=is_answer ? (rx_arg[2] ? 2'd1 : 2'd2) : 2'd0;
                            end else if(is_finish) begin
                                // Commit this transaction in LOAD_WAIT on the following cycle.
                                state<=LOAD_WAIT;
                            end else begin reply_cmd<=8'he0; reply_arg<=8'h40; state<=REPLY; end
                        end
                    end
                end
                LOAD_SEND: begin
                    // Drive the question LEDs from the accepted packet, outside the sequence/duplicate decode path.
                    if(saved_cmd==8'h21) correct_questions[saved_page-8'd9]<=saved_arg[2];
                    if(page_ready) state<=LOAD_WAIT;
                    else if(storage_error==8'h10 || storage_error==8'h11 || storage_error==8'h32 || storage_error==8'h33 || storage_error==8'h34) begin
                        reply_cmd<=8'he0; reply_arg<=storage_error; state<=REPLY;
                    end
                end
                LOAD_WAIT: begin
                    if(saved_cmd==8'h22) begin
                        score<=saved_arg; finished<=1; effect_mode<=2; success();
                    end else if(page_failed) begin reply_cmd<=8'he0; reply_arg<=storage_error==0 ? 8'h15 : storage_error; state<=REPLY; end
                    else if(page_done) success();
                end
                REPLY: if(tx_ready) state<=ACTIVE;
                default: state<=LEARN;
            endcase
        end
    end
endmodule
