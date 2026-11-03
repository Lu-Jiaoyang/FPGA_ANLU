`timescale 1ns/1ps
module tb_single_board;
    reg clk=0,rst_n=0,k2=1,k3=1,k4=1;
    always #5 clk=~clk;
    wire next_n,auto_n,toggle,quiz,finished,page_valid,tx,beep;
    wire [15:0] settings;
    wire [7:0] score,sel,data;
    wire [1:0] effect;
    wire [3:0] leds,page;
    reg ready=1,done=0,failed=0;
    reg [7:0] error=0;
    reg passed=0;
    reg monitor=0;
    string expected_line;
    integer lines=0;
    reg [7:0] serial_byte;
    string serial_line;
    initial forever begin
        @(negedge tx);
        if(monitor) begin
            serial_line="";
            for(integer n=0;n<32;n++) begin
                if(n!=0) @(negedge tx);
                #40;check(tx===0,"PC UART start bit");#80;
                for(integer b=0;b<8;b++) begin serial_byte[b]=tx;#80;end
                check(tx===1,"PC UART stop bit");serial_line={serial_line,serial_byte};
            end
            check(serial_line==expected_line,$sformatf("PC line [%s] expected [%s]",serial_line,expected_line));
            lines++;
        end
    end
    integer delay_count=0,requests=0,submissions=0;
    reg pending=0,submitted_q=0,hold_load=0;
    wire [1:0] review_caption;
    single_board_control #(.CLK_FREQ_HZ(1000000),.DEBOUNCE_MS(1),.LONG_HOLD_MS(10),.TIMEOUT_CYCLES(50000)) dut(
        .clk(clk),.rst_n(rst_n),.key2_n(k2),.key3_n(k3),.key4_n(k4),
        .key_next_n(next_n),.key_auto_n(auto_n),.settings_bundle(settings),
        .settings_toggle(toggle),.settings_ack(toggle),.quiz_mode(quiz),.finished(finished),
        .score(score),.effect_mode(effect),.correct_questions(leds),.page_valid(page_valid),.page_number(page),
        .page_ready(ready),.page_done(done),.page_failed(failed),.storage_error(error),.current_page(4'd1),
        .seg_sel(sel),.seg_data(data),.pc_uart_tx(tx),.buzzer_n(beep),.review_caption(review_caption));
    always @(posedge clk) begin
        done<=0;
        if(!rst_n) begin pending<=0;delay_count<=0;requests<=0;submissions<=0;submitted_q<=0;end
        else begin
            submitted_q<=dut.submitted;
            if(dut.submitted && !submitted_q) submissions<=submissions+1;
            if(page_valid && ready) begin pending<=1;delay_count<=30;requests<=requests+1;end
            else if(pending && !hold_load) begin
                if(delay_count==0) begin pending<=0;done<=1;end
                else delay_count<=delay_count-1;
            end
            if(failed) pending<=0;
        end
    end
    task cycles(input integer n);repeat(n) @(negedge clk);endtask
    task check(input bit ok,input string msg);if(!ok) $fatal(1,"single board: %s",msg);endtask
    task click(input integer key,input integer n=1100);
        @(negedge clk);
        case(key) 2:k2=0;3:k3=0;4:k4=0;endcase
        cycles(n);
        case(key) 2:k2=1;3:k3=1;4:k4=1;endcase
        cycles(1100);
    endtask
    task reset;
        rst_n=0;k2=1;k3=1;k4=1;ready=1;error=0;failed=0;hold_load=0;cycles(5);rst_n=1;cycles(1100);
    endtask
    task await_select;
        wait(dut.selecting);cycles(5);
        check(dut.selected_option==0,"each question starts at A; start key cannot leak");
    endtask
    integer expected,answer,correct,reported_score,before_review,reviewed;
    reg [3:0] mask;
    initial begin
        reset();
        check(next_n && auto_n && !quiz,"learning reset");
        k2=0;cycles(10);check(!next_n,"manual navigation passes through");k2=1;cycles(1100);
        k4=0;cycles(10);check(!auto_n,"autoplay passes through");k4=1;cycles(1100);
        click(3,12000);cycles(10);
        check(settings[10] && !quiz,"long KEY3 enters settings without quiz");
        click(4);cycles(10);check(settings[7:4]==5,"settings brightness +25%");
        click(3);cycles(10);check(settings[9:8]==1,"short KEY3 selects contrast");
        click(3);cycles(10);check(settings[9:8]==2,"short KEY3 selects period without quiz");
        for(integer n=1;n<=3;n++) begin
            click(4);cycles(10);check(settings[12:11]==n && !quiz && requests==0,"period increases without navigation/start");
        end
        click(4);cycles(10);check(settings[12:11]==3,"period upper clamp");
        for(integer n=2;n>=0;n--) begin click(2);cycles(10);check(settings[12:11]==n,"period decreases");end
        click(2);cycles(10);check(settings[12:11]==0,"period lower clamp");
        click(3);cycles(10);check(settings[9:8]==3 && settings[15:13]==4,"volume defaults to 100%");
        for(integer n=3;n>=0;n--) begin
            click(2);cycles(10);check(settings[15:13]==n && !quiz && requests==0,"volume decreases without navigation/start");
        end
        click(2);cycles(10);check(settings[15:13]==0,"mute lower clamp");
        click(4,5000);cycles(10);check(settings[15:13]==1,"held volume key changes only once");
        for(integer n=2;n<=4;n++) begin click(4);cycles(10);check(settings[15:13]==n,"volume increases");end
        click(4);cycles(10);check(settings[15:13]==4,"volume upper clamp");
        click(3);cycles(10);check(settings[9:8]==0,"menu wraps to brightness");
        click(3,12000);cycles(10);check(!settings[10] && !quiz,"long KEY3 exits settings");
        $display("ALL VOLUME MENU TESTS PASSED: defaults, clamps, held keys, four-item navigation and no key leakage");
        for(integer combo=0;combo<16;combo++) begin
            reset();expected=0;mask=0;
            monitor=1;
            click(3);await_select();
            for(integer q=0;q<4;q++) begin
                correct=q==0 ? 1 : q==1 ? 2 : q==2 ? 0 : 3;
                answer=(combo & (1<<q)) ? correct : (correct+1)%4;
                check(dut.question_index==q && page==q+5,"fixed question/image sequence");
                // Previous wraps A to D; next returns to A.
                click(3);check(dut.selected_option==3,"previous option wraps");
                click(2);check(dut.selected_option==0,"next option wraps");
                repeat(answer) click(2);
                reported_score=expected+((combo & (1<<q)) ? 25 : 0);
                expected_line=$sformatf("Q=%0d,SEL=%c,ANS=%c,OK=%0d,SCORE=%c%c%c%c%c",q+1,65+answer,65+correct,
                    (combo>>q)&1,48+reported_score/100,48+(reported_score/10)%10,48+reported_score%10,13,10);
                click(4,5000); // Holding confirm cannot advance from the explanation.
                wait(dut.answer_state==7);cycles(5);
                if(combo & (1<<q)) begin expected+=25;mask[q]=1;end
                check(dut.question_index==q && page==q+9,"held confirm submits once");
                check(dut.answer_score==expected && leds==mask,"score and per-question LEDs");
                check(dut.show_correct && dut.selected_option==answer,"reveal preserves original selection");
                check(dut.answer_digits[7:4]==10+correct,"display reveals correct answer");
                check(submissions==q+1,"one PC snapshot per answer");
                check(effect==((combo & (1<<q)) ? 1 : 2),"correct/wrong feedback effect");
                click(2);check(dut.lamp_view && sel==0,"result lamp view");
                click(2);check(!dut.lamp_view,"return to digits");
                click(4);
                if(q<3) await_select();
            end
            wait(finished && dut.answer_finished);cycles(5);
            check(score==expected && effect==2 && !dut.lamp_view,"settlement score and synchronous breathing");
            click(2);check(dut.lamp_view && sel==0,"final breathing view");
            click(2);check(!dut.lamp_view,"final score view");
            before_review=requests;reviewed=0;
            if(combo==0 || combo==3) ready=0;
            if(combo==1 || combo==2 || combo==4 || combo==5) hold_load=1;
            if(combo==8) click(2);
            click(4,5000);
            check(!dut.lamp_view,"enter review returns digit output");
            if(combo==0) begin
                error=8'h32;cycles(10);
                check(dut.review_state==4 && dut.answer_digits[3:0]==14,"review dispatch storage error visible");
                error=0;ready=1;click(4);
            end
            if(combo==2) begin
                error=8'h15;failed=1;cycles(2);failed=0;cycles(3);
                check(dut.review_state==4 && dut.review_remaining==~mask,"failed load does not consume wrong question");
                error=0;hold_load=0;click(4);
            end
            if(combo==3 || combo==4) begin
                cycles(51000);check(dut.review_state==4 && dut.review_error==1,"review dispatch/commit timeout");
                ready=1;hold_load=0;cycles(100);click(4);
            end
            if(combo==1 || combo==5) begin
                check(dut.review_state==2 && !dut.review_show,"loading retains score until image commit");
                if(combo==1) begin click(4);check(dut.review_state==2,"confirm during loading is ignored");end
                else begin k4=0;cycles(2000);end
                hold_load=0;wait(dut.review_state==3);cycles(2000);
                if(combo==5) begin k4=1;cycles(1100);end
            end
            if(mask==15) begin
                check(review_caption==2 && requests==before_review,"all correct shows mastered without loading any image");
                click(4);check(review_caption==2 && requests==before_review,"all-correct repeated confirm remains safe");
            end else begin
                for(integer q=0;q<4;q++) if(!mask[q]) begin
                    wait(dut.review_state==3);cycles(5);
                    correct=q==0 ? 1 : q==1 ? 2 : q==2 ? 0 : 3;
                    check(review_caption==1 && page==q+9 && dut.review_display_index==q,"only wrong explanations in ascending order");
                    check(dut.answer_digits[3:0]==q+1 && dut.answer_digits[7:4]==10+correct,"review digits show committed question and correct option");
                    check(score==expected && dut.answer_score==expected && leds==mask && submissions==4,"review cannot rescore, alter LEDs or submit again");
                    reviewed++;click(4,5000);
                end
                check(dut.review_state==5 && review_caption==3 && !dut.review_show,"review completion returns score");
                check(score==expected && dut.answer_finished && finished,"session remains finished after review");
                if(combo!=2 && combo!=4) check(requests==before_review+reviewed,"one request per wrong explanation");
                // A second review starts from the same immutable wrong-answer list.
                click(4);wait(dut.review_state==3);cycles(5);
                check(dut.review_target==(!mask[0] ? 0 : !mask[1] ? 1 : !mask[2] ? 2 : 3),"repeated review starts from first wrong question");
                check(submissions==4 && score==expected,"repeated review leaves result untouched");
            end

        end
        monitor=0;check(lines==64,"all 64 integrated PC result lines; no extra review reports");
        $display("ALL WRONG REVIEW TESTS PASSED: 16 masks, ordered explanations, score/UART invariance, correct digits, held keys, error/retry/timeouts, repeated review and all-correct case");
        // A pre-held key during an image request must not select/submit on load completion.
        reset();ready=0;click(3);wait(page_valid);k4=0;cycles(2000);ready=1;
        await_select();cycles(2000);check(!dut.submitted,"held loading key ignored");
        k4=1;cycles(1100);click(4);wait(dut.answer_state==7);
        // A storage failure remains visible and retryable.
        reset();ready=0;click(3);wait(page_valid);error=8'h32;cycles(20);
        check(dut.comm_error==8'h32 && dut.answer_state==12,"storage failure reaches error screen");
        error=0;ready=1;click(4);await_select();
        // Shared reset clears both machines and returns to knowledge without a second board.
        reset();check(!quiz && !finished && leds==0 && score==0 && dut.answer_score==0 && review_caption==0 && dut.review_state==0,"shared reset clears review");
        passed=1;$display("PASS single-board integration: 16 score combinations, real key debounce/routing, settings, held keys, feedback view, storage error/retry and shared reset");$finish;
    end
    initial begin #100000000;$fatal(1,"single-board watchdog");end
endmodule
