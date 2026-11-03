// Lesson 10: one SDRAM read stream, frame-boundary commits and a toggle/ack CDC.
// The loader holds the page/bank bundle until the entire presentation is acknowledged.
module image_present_control #(
    parameter integer PREVIEW_FRAMES=30,
    parameter integer WIDTH=640
)(
    input wire pix_clk,rst,frame_start,
    input wire request_toggle,
    input wire [1:0] request_bank,
    input wire [3:0] request_page,
    output reg ack_toggle,
    output reg [1:0] active_bank,
    output reg [3:0] active_page,
    output reg live,
    output wire [4:0] brightness,
    output wire wipe,preview,
    output wire [9:0] wipe_columns,
    input wire [10:0] request_width,request_height,
    output reg [10:0] active_width,active_height
);
    localparam IDLE=0,FADE_OUT=1,FADE_IN=2,WIPE_IN=3,PREVIEW=4;
    (* async_reg="true" *) reg req_meta,req_sync;
    reg accepted;
    reg [2:0] state;
    reg [4:0] ramp;
    reg [7:0] preview_count;
    reg [1:0] target_bank;
    reg [3:0] target_page;
    reg [10:0] target_width,target_height;
    assign brightness=(state==FADE_OUT || state==FADE_IN) ? ramp : 5'd16;
    assign wipe=state==WIPE_IN;
    assign preview=state==PREVIEW;
    assign wipe_columns=ramp*(WIDTH/16);
    always @(posedge pix_clk or posedge rst) begin
        if(rst) begin
            req_meta<=0;req_sync<=0;accepted<=0;ack_toggle<=0;
            state<=IDLE;ramp<=16;preview_count<=0;
            target_bank<=0;target_page<=0;active_bank<=0;active_page<=0;live<=0;
            target_width<=0;target_height<=0;active_width<=0;active_height<=0;
        end else begin
            req_meta<=request_toggle;req_sync<=req_meta;
            if(frame_start) begin
                case(state)
                    IDLE:if(req_sync!=accepted) begin
                        accepted<=req_sync;target_bank<=request_bank;target_page<=request_page;
                        target_width<=request_width;target_height<=request_height;
                        if(!live || request_page==active_page) begin
                            active_bank<=request_bank;active_page<=request_page;live<=1;
                            active_width<=request_width;active_height<=request_height;
                            ack_toggle<=req_sync;
                        end else if(request_page<=4) begin
                            ramp<=16;state<=FADE_OUT;
                        end else begin
                            active_bank<=request_bank;active_page<=request_page;
                            active_width<=request_width;active_height<=request_height;
                            ramp<=0;preview_count<=0;
                            state<=request_page<=8 ? WIPE_IN : PREVIEW;
                        end
                    end
                    FADE_OUT:if(ramp!=0) ramp<=ramp-1'b1;
                        else begin
                            active_bank<=target_bank;active_page<=target_page;state<=FADE_IN;
                            active_width<=target_width;active_height<=target_height;
                        end
                    FADE_IN:if(ramp==15) begin ramp<=16;state<=IDLE;ack_toggle<=accepted;end
                        else ramp<=ramp+1'b1;
                    WIPE_IN:if(ramp==15) begin ramp<=16;state<=IDLE;ack_toggle<=accepted;end
                        else ramp<=ramp+1'b1;
                    PREVIEW:if(preview_count==PREVIEW_FRAMES-1) begin state<=IDLE;ack_toggle<=accepted;end
                        else preview_count<=preview_count+1'b1;
                    default:state<=IDLE;
                endcase
            end
        end
    end
endmodule
