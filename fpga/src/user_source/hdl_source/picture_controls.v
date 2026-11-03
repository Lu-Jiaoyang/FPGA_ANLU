// Physical A keys: KEY3 long opens/closes; short selects BRT/CON/INT/VOL in menu.
// KEY2 decreases, KEY4 increases. Outside the menu the existing keys pass through.
module picture_controls #(
    parameter integer CLK_FREQ_HZ=100000000,
    parameter integer DEBOUNCE_MS=20,
    parameter integer LONG_HOLD_MS=1000
)(
    input clk,rst_n,key2_n,key3_n,key4_n,
    output key_next_n,key_auto_n,
    output reg start_quiz,
    output reg [15:0] settings_bundle,
    output reg settings_toggle,
    input settings_ack
);
    localparam integer HOLD_CYCLES=(CLK_FREQ_HZ/1000)*LONG_HOLD_MS;
    localparam integer HOLD_BITS=HOLD_CYCLES>1 ? $clog2(HOLD_CYCLES+1) : 1;
    wire s2,s3,s4,p2,p4;
    key_press_debounce #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.DEBOUNCE_MS(DEBOUNCE_MS)) k2(
        .clk(clk),.rst(!rst_n),.button_in(key2_n),.press_pulse(p2),.button_stable_out(s2));
    key_press_debounce #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.DEBOUNCE_MS(DEBOUNCE_MS)) k3(
        .clk(clk),.rst(!rst_n),.button_in(key3_n),.press_pulse(),.button_stable_out(s3));
    key_press_debounce #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.DEBOUNCE_MS(DEBOUNCE_MS)) k4(
        .clk(clk),.rst(!rst_n),.button_in(key4_n),.press_pulse(p4),.button_stable_out(s4));
    reg menu,rearm,s3_d,long_used;
    reg [1:0] selection,period;
    reg [3:0] bright,contrast;
    reg [2:0] volume;
    reg [HOLD_BITS-1:0] hold_count;
    (* async_reg="true" *) reg [1:0] ack_sync;
    wire [15:0] desired={volume,period,menu,selection,bright,contrast};
    assign key_next_n=(menu || rearm) ? 1'b1 : key2_n;
    assign key_auto_n=(menu || rearm) ? 1'b1 : key4_n;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            menu<=0;selection<=0;period<=0;rearm<=0;s3_d<=1;long_used<=0;hold_count<=0;
            bright<=4;contrast<=4;volume<=4;start_quiz<=0;
            settings_bundle<=16'h8044;settings_toggle<=0;ack_sync<=0;
        end else begin
            start_quiz<=0;s3_d<=s3;ack_sync<={ack_sync[0],settings_ack};
            // A stable bundle stays frozen until the pixel domain acknowledges its frame commit.
            if(ack_sync[1]==settings_toggle && settings_bundle!=desired) begin
                settings_bundle<=desired;settings_toggle<=~settings_toggle;
            end
            if(rearm && s2 && s3 && s4 && key2_n && key3_n && key4_n) rearm<=0;
            if(s3) begin
                hold_count<=0;long_used<=0;
                if(!s3_d && !long_used) begin
                    if(menu) selection<=selection+1'b1;
                    else if(!rearm) start_quiz<=1;
                end
            end else if(!long_used) begin
                if(hold_count<HOLD_CYCLES-1) hold_count<=hold_count+1'b1;
                else if(s2 && s4 && key2_n && key4_n) begin
                    menu<=~menu;long_used<=1;rearm<=1;
                end
            end
            if(menu && !rearm && (p2 ^ p4)) begin
                if(selection==3) begin
                    if(p4 && volume<4) volume<=volume+1'b1;
                    else if(p2 && volume>0) volume<=volume-1'b1;
                end else if(selection==2) begin
                    if(p4 && period<3) period<=period+1'b1;
                    else if(p2 && period>0) period<=period-1'b1;
                end else if(selection==1) begin
                    if(p4 && contrast<8) contrast<=contrast+1'b1;
                    else if(p2 && contrast>0) contrast<=contrast-1'b1;
                end else begin
                    if(p4 && bright<8) bright<=bright+1'b1;
                    else if(p2 && bright>0) bright<=bright-1'b1;
                end
            end
        end
    end
endmodule
