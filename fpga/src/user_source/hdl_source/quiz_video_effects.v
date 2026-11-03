// Lesson 9 pixel overlay + lesson 10 frame-constant effects; one-cycle RGB/timing pipeline.
module quiz_video_effects #(
    parameter BOOT_FILE="C:/Users/lenovo/Downloads/FPGA_submission_20261031_final/science_learning_system/fpga/src/user_source/hdl_source/boot_pic01.dath"
)(
    input wire pix_clk,rst,
    input wire hs,vs,de,
    input wire [23:0] rgb,
    input wire live,
    input wire [4:0] brightness,
    input wire [3:0] user_brightness,user_contrast,
    input wire wipe,preview,
    input wire [9:0] wipe_columns,
    input wire [7:0] storage_error,
    input wire load_clk,load_rst,load_start,pixel_write,
    input wire [23:0] load_rgb,
    output reg hs_out,vs_out,de_out,
    output wire [23:0] rgb_out
);
    (* ram_style="bram" *) reg [15:0] thumbnail[0:4799];
    reg [9:0] load_x;
    reg [8:0] load_y;
    reg [12:0] thumb_row;
    wire [12:0] thumb_write_addr=thumb_row+{6'd0,load_x[9:3]};
    always @(posedge load_clk or posedge load_rst) begin
        if(load_rst) begin load_x<=0;load_y<=0;thumb_row<=13'd4720;end
        else if(load_start) begin load_x<=0;load_y<=0;thumb_row<=13'd4720;end
        else if(pixel_write) begin
            if(load_x==639) begin
                load_x<=0;load_y<=load_y+1'b1;
                if(load_y[2:0]==7 && load_y<479) thumb_row<=thumb_row-13'd80;
            end else load_x<=load_x+1'b1;
        end
    end
    // Source BMP is bottom-up; the row address reverses the downsampled image.
    always @(posedge load_clk)
        if(pixel_write && !load_rst && load_x[2:0]==0 && load_y[2:0]==7)
            thumbnail[thumb_write_addr]<={load_rgb[23:19],load_rgb[15:10],load_rgb[7:3]};

    reg de_d,vs_d;
    reg [9:0] x;
    reg [8:0] y;
    wire [9:0] px=de_d ? x : 10'd0;
    wire thumb_inside=px>=240 && px<400 && y>=180 && y<300;
    wire thumb_border=px>=238 && px<402 && y>=178 && y<302 && !thumb_inside;
    wire [9:0] tx=px-240;
    wire [8:0] ty=y-180;
    wire [13:0] boot_addr={7'd0,y[8:2]}*14'd80+{7'd0,px[9:3]};
    wire [12:0] thumb_addr={6'd0,ty[7:1]}*13'd80+{6'd0,tx[7:1]};
    wire [15:0] boot_word;
    reg boot_half;
    wire [7:0] boot_q=boot_half ? boot_word[15:8] : boot_word[7:0];
    reg [15:0] thumb_q;
    reg [23:0] rgb_q;
    reg live_q,preview_q,inside_q,border_q,wipe_hidden_q,status_q,error_q;
    reg [4:0] fade_q;
    reg [7:0] error_meta,error_sync,error_frame;
    always @(posedge pix_clk or posedge rst) begin
        if(rst) begin
            de_d<=0;vs_d<=0;x<=0;y<=0;hs_out<=0;vs_out<=0;de_out<=0;
            rgb_q<=0;live_q<=0;preview_q<=0;inside_q<=0;border_q<=0;wipe_hidden_q<=0;
            status_q<=0;error_q<=0;error_meta<=0;error_sync<=0;error_frame<=0;
            fade_q<=16;
        end else begin
            de_d<=de;vs_d<=vs;
            error_meta<=storage_error;error_sync<=error_meta;
            if(vs_d && !vs) begin y<=0;error_frame<=error_sync;end
            else if(de_d && !de) y<=y+1'b1;
            if(de) x<=px+1'b1;else x<=0;
            hs_out<=hs;vs_out<=vs;de_out<=de;rgb_q<=rgb;
            live_q<=live;preview_q<=preview;inside_q<=thumb_inside;border_q<=thumb_border;
            wipe_hidden_q<=wipe && px>=wipe_columns;
            status_q<=!live && px<12 && y<12;error_q<=error_frame!=0;
            fade_q<=brightness;
        end
    end
    always @(posedge pix_clk) begin
        if(de) boot_half<=px[2];
        if(de && thumb_inside) thumb_q<=thumbnail[thumb_addr];
    end
    // Explicit EG4 ROM avoids TD expanding this initialized image into LUTs.
    EG_LOGIC_BRAM #(.DATA_WIDTH_A(16),.DATA_WIDTH_B(16),.ADDR_WIDTH_A(14),.ADDR_WIDTH_B(14),
        .DATA_DEPTH_A(9600),.DATA_DEPTH_B(9600),.MODE("SP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
        .INIT_FILE(BOOT_FILE),.IMPLEMENT("9K")) boot_rom(
        .doa(boot_word),.dob(),.dia(16'd0),.dib(16'd0),.cea(de),.ceb(1'b0),.ocea(1'b1),.oceb(1'b0),
        .clka(pix_clk),.clkb(1'b0),.wea(1'b0),.web(1'b0),.rsta(1'b0),.rstb(1'b0),
        .bea(1'b0),.beb(1'b0),.addra(boot_addr),.addrb(14'd0));
    wire [23:0] boot_rgb={{boot_q[7:5],boot_q[7:5],boot_q[7:6]},
                         {boot_q[4:2],boot_q[4:2],boot_q[4:3]},
                         {boot_q[1:0],boot_q[1:0],boot_q[1:0],boot_q[1:0]}};
    wire [23:0] thumb_rgb={thumb_q[15:11],thumb_q[15:13],thumb_q[10:5],thumb_q[10:9],thumb_q[4:0],thumb_q[4:2]};
    wire [23:0] selected_rgb=
        !live_q ? (status_q ? (error_q ? 24'hff3030 : 24'hffb030) : boot_rgb) :
        preview_q ? (inside_q ? thumb_rgb : border_q ? 24'hffffff : rgb_q) : rgb_q;
    wire [4:0] envelope=!live_q ? 5'd16 : preview_q ?
        (inside_q || border_q ? 5'd16 : 5'd4) : wipe_hidden_q ? 5'd0 : fade_q;
    wire [23:0] adjusted;
    picture_tone tone(.rgb(selected_rgb),.bright(user_brightness),.contrast(user_contrast),
        .fade(envelope),.adjusted(adjusted));
    assign rgb_out=de_out ? adjusted : 24'd0;
endmodule
