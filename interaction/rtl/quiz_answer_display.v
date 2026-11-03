module quiz_answer_display #(parameter integer CLK_FREQ_HZ=50000000)(
    input wire clk,rst_n,selecting,submitted,answer_correct,show_correct,finished,
    input wire [1:0] question_index,selected_option,correct_option,
    input wire [7:0] score,comm_error,
    input wire [3:0] state,
    output reg [31:0] digits,
    output wire [3:0] led_status
);
    localparam integer HALF=CLK_FREQ_HZ/2, CW=$clog2(HALF);
    reg [CW-1:0] count;
    reg visible,was_selecting,was_finished;
    wire [11:0] score_value;
    score_digits u_score(score,score_value);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin count<=0; visible<=1; was_selecting<=0; was_finished<=0; end
        else begin
            was_selecting<=selecting; was_finished<=finished;
            if((selecting && !was_selecting) || (finished && !was_finished) || (!selecting && !finished)) begin
                count<=0; visible<=1;
            end else if(count==HALF-1) begin count<=0; visible<=~visible; end
            else count<=count+1'b1;
        end
    end
    assign led_status=submitted && (answer_correct || show_correct) && !finished ? (4'b1 << correct_option) : 4'b0;
    always @* begin
        digits=32'hffffffff;
        if(finished) begin if(visible) digits[11:0]=score_value; end
        else if(comm_error!=0) begin
            digits[3:0]=4'he; digits[7:4]=comm_error[7:4]; digits[11:8]=comm_error[3:0];
        end else if(state!=0 && state!=1) begin
            digits[3:0]={2'b0,question_index}+4'd1;
            if(!selecting || visible) digits[7:4]=4'ha+{2'b0,(show_correct ? correct_option : selected_option)};
        end
    end
endmodule
