// A5 CMD SEQ PAGE ARG XOR 5A. No command/page numbers are defined here.
// tx_valid/tx_ready handshake latches all fields. busy covers the final stop bit.
module uart_frame_link #(
    parameter integer CLK_FREQ_HZ=50000000,BAUD=9600,
    parameter integer RX_TIMEOUT_CYCLES=(CLK_FREQ_HZ/1000)*50
)(
    input wire clk,rst_n,rx,
    output wire tx,
    input wire tx_valid,
    input wire [7:0] tx_cmd,tx_seq,tx_page,tx_arg,
    output wire tx_ready,tx_busy,
    output reg rx_valid,
    output reg [7:0] rx_cmd,rx_seq,rx_page,rx_arg,
    output reg check_error,tail_error,partial_timeout,
    output wire uart_error
);
    wire byte_busy,byte_valid;
    wire [7:0] received_byte;
    reg byte_start;
    reg [7:0] byte_data;
    reg [2:0] send_index,send_state;
    reg [7:0] saved_cmd,saved_seq,saved_page,saved_arg;
    localparam TX_IDLE=0,TX_LAUNCH=1,TX_ACCEPT=2,TX_WAIT=3;
    assign tx_ready=send_state==TX_IDLE;
    assign tx_busy=!tx_ready;
    uart_tx #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.BAUD(BAUD)) u_tx(
        .clk(clk),.rst_n(rst_n),.start(byte_start),.data(byte_data),.tx(tx),.busy(byte_busy));
    uart_rx #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.BAUD(BAUD)) u_rx(
        .clk(clk),.rst_n(rst_n),.rx(rx),.data(received_byte),.valid(byte_valid),.frame_error(uart_error));
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            byte_start<=0;byte_data<=0;send_index<=0;send_state<=TX_IDLE;
            saved_cmd<=0;saved_seq<=0;saved_page<=0;saved_arg<=0;
        end else begin
            byte_start<=0;
            case(send_state)
                TX_IDLE:if(tx_valid) begin
                    saved_cmd<=tx_cmd;saved_seq<=tx_seq;saved_page<=tx_page;saved_arg<=tx_arg;
                    send_index<=0;send_state<=TX_LAUNCH;
                end
                TX_LAUNCH:if(!byte_busy) begin
                    case(send_index)
                        0:byte_data<=8'hA5;1:byte_data<=saved_cmd;2:byte_data<=saved_seq;
                        3:byte_data<=saved_page;4:byte_data<=saved_arg;
                        5:byte_data<=saved_cmd^saved_seq^saved_page^saved_arg;
                        6:byte_data<=8'h5A;
                        default:byte_data<=8'h5A;
                    endcase
                    byte_start<=1;send_state<=TX_ACCEPT;
                end
                TX_ACCEPT:if(byte_busy) send_state<=TX_WAIT;
                TX_WAIT:if(!byte_busy) begin
                    if(send_index==6) send_state<=TX_IDLE;
                    else begin send_index<=send_index+1'b1;send_state<=TX_LAUNCH;end
                end
                default:send_state<=TX_IDLE;
            endcase
        end
    end
    localparam integer RW=RX_TIMEOUT_CYCLES<2 ? 1 : $clog2(RX_TIMEOUT_CYCLES);
    reg [RW-1:0] rx_timer;
    reg [2:0] receive_index;
    reg [7:0] c,s,p,a,check;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            rx_timer<=0;receive_index<=0;rx_valid<=0;rx_cmd<=0;rx_seq<=0;rx_page<=0;rx_arg<=0;
            check_error<=0;tail_error<=0;partial_timeout<=0;c<=0;s<=0;p<=0;a<=0;check<=0;
        end else begin
            rx_valid<=0;check_error<=0;tail_error<=0;partial_timeout<=0;
            if(uart_error) begin receive_index<=0;rx_timer<=0;end
            else if(byte_valid) begin
                rx_timer<=0;
                case(receive_index)
                    0:if(received_byte==8'hA5) receive_index<=1;
                    1:begin c<=received_byte;receive_index<=2;end
                    2:begin s<=received_byte;receive_index<=3;end
                    3:begin p<=received_byte;receive_index<=4;end
                    4:begin a<=received_byte;receive_index<=5;end
                    5:begin check<=received_byte;receive_index<=6;end
                    6:begin
                        receive_index<=received_byte==8'hA5 ? 1 : 0;
                        if(received_byte!=8'h5A) tail_error<=1;
                        else if(check!=(c^s^p^a)) check_error<=1;
                        else begin rx_cmd<=c;rx_seq<=s;rx_page<=p;rx_arg<=a;rx_valid<=1;end
                    end
                    default:receive_index<=0;
                endcase
            end else if(receive_index!=0) begin
                if(rx_timer==RX_TIMEOUT_CYCLES-1) begin receive_index<=0;rx_timer<=0;partial_timeout<=1;end
                else rx_timer<=rx_timer+1'b1;
            end
        end
    end
endmodule
