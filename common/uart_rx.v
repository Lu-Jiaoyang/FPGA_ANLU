// 8N1, LSB first, active-low reset. Use at least 8 clocks per bit.
// valid/frame_error are one-clock pulses; data holds the last valid byte.
module uart_rx #(
    parameter integer CLK_FREQ_HZ=50000000,BAUD=9600
)(
    input wire clk,rst_n,rx,
    output reg [7:0] data,
    output reg valid,frame_error
);
    localparam integer CPB=CLK_FREQ_HZ/BAUD,CW=CPB<2 ? 1 : $clog2(CPB);
    localparam IDLE=0,START=1,DATA=2,STOP=3,RECOVER=4;
    reg [2:0] state,bit_index;
    reg [CW-1:0] count;
    reg [7:0] shift;
    reg rx_meta,rx_sync;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin rx_meta<=1;rx_sync<=1;end
        else begin rx_meta<=rx;rx_sync<=rx_meta;end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;count<=0;bit_index<=0;shift<=0;data<=0;valid<=0;frame_error<=0;
        end else begin
            valid<=0;frame_error<=0;
            case(state)
                IDLE:if(!rx_sync) begin state<=START;count<=CPB/2-1;end
                START:if(count!=0) count<=count-1'b1;
                    else if(rx_sync) state<=IDLE;
                    else begin state<=DATA;count<=CPB-1;bit_index<=0;end
                DATA:if(count!=0) count<=count-1'b1;
                    else begin
                        shift[bit_index]<=rx_sync;count<=CPB-1;
                        if(bit_index==7) state<=STOP;else bit_index<=bit_index+1'b1;
                    end
                STOP:if(count!=0) count<=count-1'b1;
                    else if(rx_sync) begin data<=shift;valid<=1;state<=IDLE;end
                    else begin frame_error<=1;state<=RECOVER;end
                RECOVER:if(rx_sync) state<=IDLE;
                default:state<=IDLE;
            endcase
        end
    end
endmodule
