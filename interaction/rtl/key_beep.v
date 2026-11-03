// Passive buzzer: 2 kHz square wave for 80 ms, idle high (SW5 down).
module key_beep #(parameter integer CLK_FREQ_HZ=50000000)(
    input wire clk,rst_n,trigger, output wire buzzer_n
);
    localparam integer DURATION=CLK_FREQ_HZ/1000*80, HALF=CLK_FREQ_HZ/4000;
    reg [$clog2(DURATION)-1:0] remaining;
    reg [$clog2(HALF)-1:0] divider;
    reg wave;
    assign buzzer_n=remaining!=0 ? wave : 1'b1;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin remaining<=0; divider<=0; wave<=1; end
        else if(trigger) begin remaining<=DURATION; divider<=0; wave<=0; end
        else if(remaining!=0) begin
            remaining<=remaining-1'b1;
            if(divider==HALF-1) begin divider<=0; wave<=~wave; end
            else divider<=divider+1'b1;
        end else begin divider<=0; wave<=1; end
    end
endmodule
