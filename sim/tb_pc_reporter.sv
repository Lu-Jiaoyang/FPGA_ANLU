`timescale 1ns/1ps
module tb_pc_reporter;
    reg clk=0,rst_n=0,submitted=0,result=0;
    reg [1:0] question=0,selected=0,correct=0;
    reg [7:0] score=0;
    wire tx;
    reg passed=0;
    localparam integer BIT_NS=8680; // 100 MHz / floor(100 MHz / 115200).
    always #5 clk=~clk;
    quiz_pc_reporter #(.CLK_FREQ_HZ(100000000)) dut(clk,rst_n,submitted,question,selected,correct,result,score,tx);

    task receive_line(input string expected_line);
        reg [7:0] value;
        string line;
        begin
            line="";
            for(integer n=0;n<32;n=n+1) begin
                @(negedge tx);#(BIT_NS/2);
                if(tx!==0) $fatal(1,"start bit");
                #(BIT_NS);
                for(integer bitno=0;bitno<8;bitno=bitno+1) begin
                    value[bitno]=tx;#(BIT_NS);
                end
                if(tx!==1) $fatal(1,"stop bit");
                line={line,value};
            end
            if(line!=expected_line) $fatal(1,"snapshot line [%s] expected [%s]",line,expected_line);
        end
    endtask
    task assert_idle;
        begin
            repeat(160000) begin @(negedge clk);if(tx!==1) $fatal(1,"unexpected retransmission");end
        end
    endtask
    initial begin
        repeat(4) @(negedge clk);rst_n=1;
        question=1;selected=3;correct=2;result=0;score=25;
        @(negedge clk);submitted=1;
        fork
            receive_line($sformatf("Q=2,SEL=D,ANS=C,OK=0,SCORE=025%c%c",13,10));
            begin
                repeat(100) @(negedge clk);
                question=3;selected=0;correct=3;result=1;score=100;
            end
        join
        #(BIT_NS);assert_idle(); // Holding submitted must never re-send.
        submitted=0;repeat(4) @(negedge clk);submitted=1;
        receive_line($sformatf("Q=4,SEL=A,ANS=D,OK=1,SCORE=100%c%c",13,10));
        #(BIT_NS);
        submitted=0;repeat(4) @(negedge clk);submitted=1;
        @(negedge tx);#(BIT_NS*3);rst_n=0;submitted=0;
        repeat(4) @(negedge clk);
        if(tx!==1) $fatal(1,"reset must abort transmission to idle");
        rst_n=1;assert_idle();
        question=0;selected=0;correct=1;result=0;score=0;
        @(negedge clk);submitted=1;
        receive_line($sformatf("Q=1,SEL=A,ANS=B,OK=0,SCORE=000%c%c",13,10));
        #(BIT_NS);assert_idle();
        $display("ALL PC REPORTER TESTS PASSED: real 100MHz/115200 timing, atomic snapshot, held submission, mid-line reset and clean restart");
        passed=1;$finish;
    end
    initial begin #40000000;$fatal(1,"PC reporter watchdog");end
endmodule
