// Read-only PC telemetry; independent of the acknowledged A/B link.
module quiz_pc_reporter #(
    parameter integer CLK_FREQ_HZ=50000000, BAUD=115200
)(
    input wire clk,rst_n,submitted,
    input wire [1:0] question_index,selected_option,correct_option,
    input wire answer_correct,
    input wire [7:0] score,
    output wire tx
);
    reg submitted_q,sending,start;
    reg [4:0] index;
    reg [7:0] data;
    reg [1:0] question,selected,correct;
    reg result;
    reg [7:0] points;
    wire busy;
    uart_tx #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.BAUD(BAUD)) transmitter(
        .clk(clk),.rst_n(rst_n),.start(start),.data(data),.tx(tx),.busy(busy));

    reg [7:0] next_byte;
    always @* begin
        case(index)
            0:next_byte=8'h51;
            1:next_byte=8'h3d;
            2:next_byte=8'h31+{6'd0,question};
            3:next_byte=8'h2c;
            4:next_byte=8'h53;
            5:next_byte=8'h45;
            6:next_byte=8'h4c;
            7:next_byte=8'h3d;
            8:next_byte=8'h41+{6'd0,selected};
            9:next_byte=8'h2c;
            10:next_byte=8'h41;
            11:next_byte=8'h4e;
            12:next_byte=8'h53;
            13:next_byte=8'h3d;
            14:next_byte=8'h41+{6'd0,correct};
            15:next_byte=8'h2c;
            16:next_byte=8'h4f;
            17:next_byte=8'h4b;
            18:next_byte=8'h3d;
            19:next_byte=result ? "1" : "0";
            20:next_byte=8'h2c;
            21:next_byte=8'h53;
            22:next_byte=8'h43;
            23:next_byte=8'h4f;
            24:next_byte=8'h52;
            25:next_byte=8'h45;
            26:next_byte=8'h3d;
            27:next_byte=8'h30+points/100;
            28:next_byte=8'h30+(points/10)%10;
            29:next_byte=8'h30+points%10;
            30:next_byte=8'h0d;
            31:next_byte=8'h0a;
            default:next_byte=8'h0a;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            submitted_q<=0;sending<=0;start<=0;index<=0;data<=0;
            question<=0;selected<=0;correct<=0;result<=0;points<=0;
        end else begin
            submitted_q<=submitted;
            start<=0;
            // shortcut: no queue; this <3ms line finishes before the next 20ms-debounced answer.
            // Add a FIFO if machine-generated submissions replace the physical keys.
            if(submitted && !submitted_q && !sending && !busy) begin
                question<=question_index;selected<=selected_option;correct<=correct_option;
                result<=answer_correct;points<=score;index<=0;sending<=1;
            end
            if(sending && !busy && !start) begin
                data<=next_byte;start<=1;
                if(index==31) sending<=0;
                else index<=index+1'b1;
            end
        end
    end
endmodule
