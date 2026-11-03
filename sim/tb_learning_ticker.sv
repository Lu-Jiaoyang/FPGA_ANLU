`timescale 1ns/1ps
module tb_learning_ticker;
    reg clk=0,rst=1,hs=1,vs=1,de=0,autoplay=0;
    reg [3:0] page=1;
    reg [23:0] rgb=0;
    wire oh,ov,od;
    wire [23:0] pixel;
    reg [255:0] font[0:11];
    reg passed=0;
    integer frames=0,checked=0,white_pixels=0;
    always #5 clk=~clk;
    quiz_feedback_subtitle dut(clk,rst,hs,vs,de,rgb,page,1'b0,autoplay,oh,ov,od,pixel,2'd0);

    task new_frame;
        begin
            @(negedge clk);de=0;vs=1;
            repeat(4) @(negedge clk);
            vs=0;repeat(3) @(negedge clk);vs=1;
            frames=frames+1;
        end
    endtask

    task scan(input integer offset,input integer enabled,input integer stop_midframe);
        integer x,y,u,id,col,row;
        reg [23:0] expected_pixel;
        begin
            for(y=0;y<480;y=y+1) begin
                for(x=0;x<640;x=x+1) begin
                    @(negedge clk);de=1;hs=1;
                    rgb=24'h204080 ^ (x*17+y*193);
                    if(stop_midframe && y==100 && x==320) autoplay=0;
                    expected_pixel=rgb;
                    if(enabled && y>=450 && y<470) begin
                        expected_pixel=24'h101820;
                        u=x-(640-offset);row=y-452;
                        if(u>=0 && u<216 && row>=0 && row<16) begin
                            id=u/18;col=u-id*18;
                            if(col<16 && font[id][255-row*16-col]) begin
                                expected_pixel=24'hffffff;
                                white_pixels=white_pixels+1;
                            end
                        end
                    end
                    @(posedge clk);#1;
                    if(oh!==hs || ov!==vs || od!==de || pixel!==expected_pixel)
                        $fatal(1,"ticker raster mismatch frame=%0d x=%0d y=%0d offset=%0d got=%h want=%h",frames,x,y,offset,pixel,expected_pixel);
                    checked=checked+1;
                end
                @(negedge clk);de=0;hs=0;
                @(posedge clk);#1;
                if(pixel!==0 || oh!==0 || od!==0) $fatal(1,"blanking alignment");
                repeat(2) @(negedge clk);
            end
        end
    endtask

    initial begin
        $readmemh("sim/project_title_glyphs.mem",font);
        repeat(4) @(negedge clk);rst=0;
        new_frame();scan(0,0,0);
        autoplay=1;
        new_frame();scan(0,1,0);
        repeat(16) new_frame();scan(16,1,0);
        repeat(200) new_frame();scan(216,1,0);
        repeat(212) new_frame();scan(428,1,0);
        repeat(212) new_frame();scan(640,1,0);
        repeat(215) new_frame();scan(855,1,0);
        new_frame();scan(0,1,0);
        repeat(216) new_frame();scan(216,1,1);
        new_frame();scan(0,0,0);
        autoplay=1;page=5;
        new_frame();scan(0,0,0);
        page=4;new_frame();scan(0,1,0);
        new_frame();scan(1,1,0);
        rst=1;repeat(3) @(negedge clk);rst=0;autoplay=0;
        new_frame();scan(0,0,0);
        if(white_pixels<2000) $fatal(1,"missing text glyphs");
        if(checked!=4300800) $fatal(1,"incomplete raster checks");
        $display("ALL PROJECT TITLE TICKER TESTS PASSED: 14 full frames, 4300800 exact pixels, right-to-left, wrap, frame atomic stop, quiz hide, reset and sync");
        passed=1;$finish;
    end
    initial begin #100000000;$fatal(1,"ticker watchdog");end
endmodule
