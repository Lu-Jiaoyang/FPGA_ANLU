// Normalize one bottom-up BMP stream before the existing frame writer.
// Lesson 12 coordinate mapping; exact 2:1 reduction uses a rounded 2x2 box filter.
module bmp_resize_stream(
    input clk,rst,start,
    input [10:0] source_width,source_height,
    input [15:0] target_width,target_height,
    input in_valid,
    output in_ready,
    input [23:0] in_rgb,
    output reg out_valid,
    output reg [23:0] out_rgb,
    output reg done
);
    localparam IDLE=0,ACCEPT=1,WORK=2,X_STEP=3,PIXEL_END=4,
               ROW_READ=5,ROW_EMIT=6,Y_STEP=7,ROW_END=8,BOX_READ=9,BOX_EMIT=10;
    reg [3:0] state;
    reg [10:0] sx,sy,want_x,want_y;
    reg [9:0] dx,read_x;
    reg [15:0] dy;
    reg [12:0] x_error,y_error;
    reg [23:0] held,first;
    reg [26:0] pair_sum;
    reg [3:0] cooldown;
    wire box_mode=({5'd0,source_width}==target_width*2 &&
                   {5'd0,source_height}==target_height*2);
    // shortcut: stretch to the output aspect ratio; add letterboxing only if requested.
    wire [26:0] line_q;
    wire [26:0] horizontal_sum={
        ({1'b0,first[23:16]}+{1'b0,held[23:16]}),
        ({1'b0,first[15:8]}+{1'b0,held[15:8]}),
        ({1'b0,first[7:0]}+{1'b0,held[7:0]})};
    wire [9:0] r_sum={1'b0,line_q[26:18]}+{1'b0,pair_sum[26:18]}+10'd2;
    wire [9:0] g_sum={1'b0,line_q[17:9]}+{1'b0,pair_sum[17:9]}+10'd2;
    wire [9:0] b_sum={1'b0,line_q[8:0]}+{1'b0,pair_sum[8:0]}+10'd2;
    assign in_ready=state==ACCEPT && !rst && !start;
    wire line_write=state==WORK && !rst && !start &&
        (box_mode ? sx[0] && !sy[0] : dx<target_width && sx==want_x);
    wire line_read=state==ROW_READ || state==BOX_READ;
    wire [9:0] line_addr=line_write ? (box_mode ? sx[10:1] : dx) :
        (state==BOX_READ ? sx[10:1] : read_x);
    wire [26:0] line_data=box_mode ? horizontal_sum :
        {1'b0,held[23:16],1'b0,held[15:8],1'b0,held[7:0]};
    // TD otherwise expands the two-address procedural read into distributed LUT RAM.
    EG_LOGIC_BRAM #(.DATA_WIDTH_A(27),.DATA_WIDTH_B(27),.ADDR_WIDTH_A(10),.ADDR_WIDTH_B(10),
        .DATA_DEPTH_A(640),.DATA_DEPTH_B(640),.MODE("SP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
        .IMPLEMENT("9K")) line_store(
        .doa(line_q),.dob(),.dia(line_data),.dib(27'd0),.cea(line_write || line_read),.ceb(1'b0),
        .ocea(1'b1),.oceb(1'b0),.clka(clk),.clkb(1'b0),.wea(line_write),.web(1'b0),
        .rsta(1'b0),.rstb(1'b0),.bea(1'b0),.beb(1'b0),.addra(line_addr),.addrb(10'd0));
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            state<=IDLE;sx<=0;sy<=0;want_x<=0;want_y<=0;dx<=0;dy<=0;
            read_x<=0;x_error<=0;y_error<=0;held<=0;first<=0;pair_sum<=0;
            out_valid<=0;out_rgb<=0;done<=0;cooldown<=0;
        end else begin
            out_valid<=0;
            if(cooldown!=0) cooldown<=cooldown-1'b1;
            if(start) begin
                state<=ACCEPT;sx<=0;sy<=0;want_x<=0;want_y<=0;dx<=0;dy<=0;
                read_x<=0;x_error<=0;y_error<=0;done<=0;cooldown<=0;
            end else case(state)
                IDLE:;
                ACCEPT:if(in_valid) begin held<=in_rgb;state<=WORK;end
                WORK:if(box_mode) begin
                    if(!sx[0]) begin first<=held;state<=PIXEL_END;end
                    else if(!sy[0]) state<=PIXEL_END;
                    else begin pair_sum<=horizontal_sum;state<=BOX_READ;end
                end else if(dx<target_width && sx==want_x) begin
                    dx<=dx+1'b1;x_error<=x_error+source_width;state<=X_STEP;
                end else state<=PIXEL_END;
                X_STEP:if(x_error>=target_width) begin
                    x_error<=x_error-target_width;want_x<=want_x+1'b1;
                end else state<=WORK;
                PIXEL_END:if(sx==source_width-1'b1) begin
                    read_x<=0;
                    if(!box_mode && sy==want_y && dy<target_height) state<=ROW_READ;
                    else state<=ROW_END;
                end else begin sx<=sx+1'b1;state<=ACCEPT;end
                ROW_READ:state<=ROW_EMIT;
                ROW_EMIT:if(cooldown==0) begin
                    out_rgb<={line_q[25:18],line_q[16:9],line_q[7:0]};
                    out_valid<=1;cooldown<=15;
                    if(read_x==target_width-1'b1) begin
                        dy<=dy+1'b1;y_error<=y_error+source_height;state<=Y_STEP;
                    end else begin read_x<=read_x+1'b1;state<=ROW_READ;end
                end
                Y_STEP:if(y_error>=target_height) begin
                    y_error<=y_error-target_height;want_y<=want_y+1'b1;
                end else if(want_y==sy && dy<target_height) begin read_x<=0;state<=ROW_READ;end
                else state<=ROW_END;
                BOX_READ:state<=BOX_EMIT;
                BOX_EMIT:if(cooldown==0) begin
                    out_rgb<={r_sum[9:2],g_sum[9:2],b_sum[9:2]};
                    out_valid<=1;cooldown<=15;state<=PIXEL_END;
                end
                ROW_END:if(sy==source_height-1'b1) begin done<=1;state<=IDLE;end
                else begin
                    sy<=sy+1'b1;sx<=0;dx<=0;want_x<=0;x_error<=0;state<=ACCEPT;
                end
                default:state<=IDLE;
            endcase
        end
    end
endmodule
