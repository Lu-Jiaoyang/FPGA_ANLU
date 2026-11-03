// B owns the answers and score; only acknowledged pages enable user input.
module quiz_answer_session #(
    parameter integer CLK_FREQ_HZ=50000000,
    parameter integer TIMEOUT_CYCLES=CLK_FREQ_HZ*12
)(
    input wire clk,rst_n,key_prev,key_next,key_confirm,
    input wire rx_valid,tx_ready,
    input wire [7:0] rx_cmd,rx_seq,rx_page,rx_arg,
    output wire tx_valid,
    output wire [7:0] tx_cmd,tx_seq,tx_page,tx_arg,
    output reg [1:0] question_index,selected_option,
    output wire [1:0] correct_option,
    output wire selecting,
    output reg submitted,answer_correct,show_correct,
    output wire finished,
    output reg [7:0] score,comm_error,
    output reg [3:0] state,
    output wire click
);
    localparam WAIT=0,PICK=1,Q_SEND=2,Q_WAIT=3,SELECT=4,E_SEND=5,E_WAIT=6,
               RESULT=7,F_SEND=9,F_WAIT=10,DONE=11,ERROR=12;
    localparam integer CW=TIMEOUT_CYCLES<2 ? 1 : $clog2(TIMEOUT_CYCLES);
    reg [CW-1:0] timer;
    reg [1:0] retries;
    reg [3:0] answered,retry_state;
    reg [7:0] seq_counter,session;
    reg session_valid;
    assign correct_option=question_index==0 ? 2'd1 : question_index==1 ? 2'd2 : question_index==2 ? 2'd0 : 2'd3;
    assign selecting=state==SELECT;
    assign finished=state==DONE;
    assign click=key_prev || key_next || key_confirm;
    assign tx_valid=state==Q_SEND || state==E_SEND || state==F_SEND;
    assign tx_cmd=(state==Q_SEND || state==Q_WAIT) ? 8'h20 : (state==E_SEND || state==E_WAIT) ? 8'h21 : 8'h22;
    assign tx_seq=seq_counter;
    assign tx_page=(state==Q_SEND || state==Q_WAIT) ? 8'd5+{6'd0,question_index} :
                   (state==E_SEND || state==E_WAIT) ? 8'd9+{6'd0,question_index} : 8'd0;
    assign tx_arg=(state==Q_SEND || state==Q_WAIT) ? 8'd0 :
                  (state==E_SEND || state==E_WAIT) ? {5'd0,answer_correct,selected_option} : score;
    wire matching=rx_valid && rx_seq==seq_counter && rx_page==tx_page;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=WAIT; question_index<=0; selected_option<=0; score<=0; answered<=0;
            submitted<=0; answer_correct<=0; show_correct<=0; comm_error<=0;
            seq_counter<=0; session<=0; session_valid<=0;
            timer<=0; retries<=0; retry_state<=Q_SEND;
        end else begin
            if(rx_valid && rx_cmd==8'h10 && rx_page==0 && rx_arg==0 && (!session_valid || rx_seq!=session)) begin
                session<=rx_seq; session_valid<=1; seq_counter<=rx_seq+8'd1;
                state<=PICK; answered<=0; score<=0; submitted<=0; answer_correct<=0;
                show_correct<=0; selected_option<=0; comm_error<=0; timer<=0; retries<=0;
            end else case(state)
                WAIT: ;
                PICK: begin
                    // Match the question numbers printed on PIC05..PIC08.
                    question_index<=!answered[0] ? 2'd0 : !answered[1] ? 2'd1 : !answered[2] ? 2'd2 : 2'd3;
                    selected_option<=0;
                    submitted<=0; answer_correct<=0; show_correct<=0;
                    timer<=0; retries<=0; state<=Q_SEND;
                end
                Q_SEND,E_SEND,F_SEND: if(tx_ready) begin
                    retry_state<=state; timer<=0; state<=state+1'b1;
                end
                Q_WAIT,E_WAIT,F_WAIT: begin
                    if(matching && rx_cmd==(tx_cmd|8'h80) && rx_arg==0) begin
                        seq_counter<=seq_counter+1'b1; timer<=0; retries<=0; comm_error<=0;
                        // Reveal only after A commits the explanation; retain the original submission for retries.
                        if(state==E_WAIT) show_correct<=1;
                        state<=state==Q_WAIT ? SELECT : state==E_WAIT ? RESULT : DONE;
                    end else if(matching && rx_cmd==8'he0) begin
                        comm_error<=rx_arg; state<=ERROR; timer<=0;
                    end else if(timer==TIMEOUT_CYCLES-1) begin
                        timer<=0;
                        if(retries==2) begin state<=ERROR; comm_error<=8'h01; end
                        else begin retries<=retries+1'b1; state<=retry_state; end
                    end else timer<=timer+1'b1;
                end
                SELECT: begin
                    if(key_prev) selected_option<=selected_option-2'd1;
                    else if(key_next) selected_option<=selected_option+2'd1;
                    else if(key_confirm) begin
                        answer_correct<=selected_option==correct_option;
                        if(selected_option==correct_option) score<=score+8'd25;
                        answered[question_index]<=1; submitted<=1; show_correct<=0;
                        timer<=0; retries<=0; state<=E_SEND;
                    end
                end
                RESULT: if(key_confirm) begin
                    if(answered==4'hf) state<=F_SEND;
                    else state<=PICK;
                end
                ERROR: if(key_confirm) begin retries<=0; timer<=0; comm_error<=0; state<=retry_state; end
                DONE: ;
                default: begin state<=WAIT; session_valid<=0; end
            endcase
        end
    end
endmodule
