`timescale 1ns/1ps
module tb_review_subtitle;
    reg clk=0,rst=1,vs=1,de=0;
    reg [1:0] caption=0;
    reg [3:0] page=9;
    wire [23:0] pixel;
    wire od,ov,oh;
    reg passed=0;
    reg [255:0] font[0:9];
    integer checked=0;
    always #5 clk=~clk;
    quiz_feedback_subtitle dut(clk,rst,1'b1,vs,de,24'h204080,page,1'b0,1'b0,oh,ov,od,pixel,caption);
    task boundary;
        @(negedge clk);de=0;vs=1;repeat(4) @(negedge clk);
        vs=0;repeat(3) @(negedge clk);vs=1;
    endtask
    task raster(input integer mode,input bit change_midframe,input string filename);
        integer id,gx,gy,cellx,celly,fd;
        reg [23:0] expected,color;
        begin
            fd=filename!="" ? $fopen(filename,"w") : 0;
            color=mode==1 ? 24'hffe060 : mode==2 ? 24'h20ff70 : 24'hffffff;
            for(integer y=0;y<480;y++) begin
                for(integer x=0;x<640;x++) begin
                    @(negedge clk);de=1;
                    if(change_midframe && y==100 && x==0) caption=3;
                    expected=24'h204080;
                    if(mode!=0 && x>=1 && x<53 && y>=150 && y<202) begin
                        expected=24'h101820;
                        cellx=(x-1)/26;celly=(y-150)/26;
                        id=mode==1 ? celly*2+cellx : mode==2 ? 4+celly*2+cellx : (celly==0 ? 2 : 8)+cellx;
                        gx=((x-1)%26)*16/24;gy=((y-150)%26)*16/24;
                        if(gx<16 && gy<16 && font[id][255-gy*16-gx]) expected=color;
                    end
                    @(posedge clk);#1;
                    if(pixel!==expected || !od || !oh || ov!==vs)
                        $fatal(1,"review subtitle mode%0d pixel(%0d,%0d): %h != %h",mode,x,y,pixel,expected);
                    checked++;
                    if(fd) $fdisplay(fd,"%06x",pixel);
                end
                @(negedge clk);de=0;repeat(2) @(negedge clk);
                if(od || pixel!=0) $fatal(1,"review subtitle blanking");
            end
            if(fd) $fclose(fd);
        end
    endtask
    initial begin
        $readmemh("sim/review_glyphs.mem",font);
        repeat(5) @(negedge clk);rst=0;caption=1;
        repeat(8) @(negedge clk);
        if(dut.review_frame!=0) $fatal(1,"review caption must wait for frame boundary");
        boundary();raster(1,1,"sim/review_caption.hex");
        boundary();raster(3,0,"");
        caption=2;boundary();raster(2,0,"");
        caption=0;page=5;boundary();raster(0,0,"");
        rst=1;@(posedge clk);#1;
        if(dut.review_frame!=0 || pixel!=0) $fatal(1,"review caption reset");
        $display("ALL REVIEW SUBTITLE TESTS PASSED: %0d exact pixels, three messages, 24x24 glyphs/gaps, frame snapshots, original image and reset",checked);
        passed=1;$finish;
    end
    initial begin #50000000;$fatal(1,"review subtitle watchdog");end
endmodule
