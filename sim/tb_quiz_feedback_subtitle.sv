`timescale 1ns/1ps
module tb_quiz_feedback_subtitle;
    reg clk=0,rst=1,hs=1,vs=1,de=0,answer_correct=0;
    reg [3:0] active_page=0;
    reg [23:0] rgb=24'h204080;
    wire hs_out,vs_out,de_out;
    wire [23:0] rgb_out;
    reg passed=0;
    integer white_count,changed_image_count;
    localparam [255:0] FIRST_CORRECT=256'h041004103FFE041004107FFF06101C883086C4C908A410A620920F0000000000;
    localparam [255:0] FIRST_WRONG=256'h404027FC344417FC0040EFFE200027FC2444244424E421986E04D0008FFE0000;
    always #5 clk=~clk;

    quiz_feedback_subtitle dut(clk,rst,hs,vs,de,rgb,active_page,answer_correct,1'b0,
        hs_out,vs_out,de_out,rgb_out,2'd0);

    task frame_start;
        begin
            @(negedge clk);de=0;vs=1;repeat(3) @(negedge clk);
            vs=0;repeat(3) @(negedge clk);vs=1;
        end
    endtask

    task scan_message(input integer count_white,input integer correct_message);
        integer x,y;
        reg [255:0] first_glyph;
        reg expected_ink;
        begin
            white_count=0;changed_image_count=0;
            first_glyph=correct_message ? FIRST_CORRECT : FIRST_WRONG;
            for(y=0;y<210;y=y+1) begin
                for(x=0;x<640;x=x+1) begin
                    @(negedge clk);de=1;
                    @(posedge clk);#1;
                    if(rgb_out==(correct_message ? 24'h20ff70 : 24'hff4040)) white_count=white_count+1;
                    if(count_white && x>=1 && x<79 && y>=150 && y<202 &&
                       (((x-1)%26)>=24 || ((y-150)%26)>=24) && rgb_out!=24'h101820)
                        $fatal(1,"stray subtitle pixel in character spacing at x=%0d y=%0d",x,y);
                    if(count_white && x>=1 && x<25 && y>=150 && y<174) begin
                        expected_ink=first_glyph[255-((y-150)*16/24)*16-((x-1)*16/24)];
                        if(rgb_out!=(expected_ink ? (correct_message ? 24'h20ff70 : 24'hff4040) : 24'h101820))
                            $fatal(1,"24x24 glyph mismatch at x=%0d y=%0d",x,y);
                    end
                    if((x<1 || x>=79 || y<150 || y>=202) && rgb_out!=rgb)
                        $fatal(1,"subtitle changed pixels outside its margin rectangle");
                    if(x>=80 && x<560 && rgb_out!=rgb) changed_image_count=changed_image_count+1;
                end
                @(negedge clk);de=0;
                repeat(2) @(negedge clk);
            end
            if(count_white && white_count<100) $fatal(1,"feedback text did not render (%0d pixels)",white_count);
            if(!count_white && white_count!=0) $fatal(1,"feedback remained after next question");
            if(changed_image_count!=0) $fatal(1,"subtitle covered image area");
        end
    endtask

    initial begin
        repeat(4) @(negedge clk);rst=0;
        answer_correct=1;active_page=9;frame_start();scan_message(1,1);
        answer_correct=0;frame_start();scan_message(1,1);
        active_page=5;frame_start();scan_message(0,0);
        answer_correct=0;active_page=10;frame_start();scan_message(1,0);
        $display("QUIZ FEEDBACK SUBTITLE TEST PASSED: 24x24 correct/wrong glyphs, clean character spacing, hold to next question, no image overlap");
        passed=1;$finish;
    end
    initial begin #100000000;$fatal(1,"subtitle test watchdog");end
endmodule
