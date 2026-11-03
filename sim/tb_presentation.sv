`timescale 1ns/1ps
module tb_presentation;
    reg clk=0,wclk=0,rst=1,frame=0,request=0;
    always #20 clk=~clk;
    always #5 wclk=~wclk;
    reg [1:0] bank=0;
    reg [3:0] page=1;
    wire ack,live,wipe,preview;
    wire [1:0] active_bank;
    wire [3:0] active_page;
    wire [4:0] brightness;
    wire [9:0] boundary;
    reg [10:0] source_width=640,source_height=480;
    wire [10:0] active_width,active_height;
    reg passed=0;
    image_present_control ctrl(clk,rst,frame,request,bank,page,ack,active_bank,active_page,live,
        brightness,wipe,preview,boundary,source_width,source_height,active_width,active_height);
    task check(input bit ok,input string msg);
        if(!ok) $fatal(1,"presentation: %s",msg);
    endtask
    task next_frame;
        begin @(negedge clk);frame=1;@(posedge clk);#1;@(negedge clk);frame=0;end
    endtask
    task send(input [3:0] p);
        reg [3:0] old_page;
        reg [10:0] old_width,old_height;
        begin
            old_page=active_page;old_width=active_width;old_height=active_height;
            @(negedge wclk);page=p;bank=~active_bank&1;
            source_width=p<=4 ? 640 : p<=8 ? 800 : 1024;
            source_height=p<=4 ? 480 : p<=8 ? 600 : 768;
            // Header changes during loading must not change the visible metadata, even at a frame boundary.
            next_frame();
            check(active_width==old_width && active_height==old_height,"preload metadata stays invisible");
            request=~request;
            repeat(5) @(negedge clk);
            check(active_page==old_page,"page cannot change mid-frame");
            check(active_width==old_width && active_height==old_height,"dimensions cannot change mid-frame");
            check(ack!=request,"request cannot be acknowledged before frame boundary");
            next_frame();
        end
    endtask
    reg [1:0] observed_bank;
    reg [4:0] observed_brightness;
    reg observed_wipe,observed_preview,observed_ack;
    always @(posedge clk) begin
        #2;
        if(!rst && !frame) check({active_bank,brightness,wipe,preview,ack}===
            {observed_bank,observed_brightness,observed_wipe,observed_preview,observed_ack},"effect/bank/ACK changed between frames");
        observed_bank=active_bank;observed_brightness=brightness;
        observed_wipe=wipe;observed_preview=preview;observed_ack=ack;
    end

    reg hs=1,vs=1,de=0,test_live=0,test_wipe=0,test_preview=0;
    reg [4:0] alpha=16;
    reg [9:0] columns=320;
    reg [23:0] rgb=0,load_rgb=0;
    reg load_start=0,pixel_write=0;
    wire ho,vo,dout;
    wire [23:0] out;
    quiz_video_effects pixels(.user_brightness(4'd4),.user_contrast(4'd4),.pix_clk(clk),.rst(rst),.hs(hs),.vs(vs),.de(de),.rgb(rgb),
        .live(test_live),.brightness(alpha),.wipe(test_wipe),.preview(test_preview),.wipe_columns(columns),
        .storage_error(8'd0),.load_clk(wclk),.load_rst(rst),.load_start(load_start),.pixel_write(pixel_write),
        .load_rgb(load_rgb),.hs_out(ho),.vs_out(vo),.de_out(dout),.rgb_out(out));
    function automatic [23:0] pattern(input integer x,input integer y);
        pattern={(8'(x)^8'(y)),8'(y),8'(x)};
    endfunction
    function automatic [23:0] quantize565(input [23:0] v);
        quantize565={v[23:19],v[23:21],v[15:10],v[15:14],v[7:3],v[7:5]};
    endfunction
    reg [15:0] boot[0:9599];
    function automatic [23:0] boot_rgb(input integer x,input integer y);
        reg [7:0] v;
        begin v=(x/4)%2 ? boot[(y/4)*80+x/8][15:8] : boot[(y/4)*80+x/8][7:0];
            boot_rgb={{v[7:5],v[7:5],v[7:6]},{v[4:2],v[4:2],v[4:3]},{v[1:0],v[1:0],v[1:0],v[1:0]}};
        end
    endfunction
    task render(input integer mode,input string filename);
        integer fd,r,g,b;
        reg [23:0] expected,v;
        begin
            @(negedge clk);de=0;vs=0;repeat(4) @(negedge clk);vs=1;repeat(4) @(negedge clk);
            test_live=mode!=0;test_wipe=mode==2;test_preview=mode==3;alpha=mode==1 ? 8 : 16;
            fd=$fopen(filename,"w");check(fd!=0,"open render output");
            for(integer y=0;y<480;y++) begin
                for(integer x=0;x<640;x++) begin
                    @(negedge clk);de=1;rgb=pattern(x,y);v=rgb;
                    if(mode==0) expected=(x<12 && y<12) ? 24'hffb030 : boot_rgb(x,y);
                    else if(mode==1) expected={1'b0,v[23:17],1'b0,v[15:9],1'b0,v[7:1]};
                    else if(mode==2) expected=x<320 ? v : 24'd0;
                    else if(x>=240 && x<400 && y>=180 && y<300)
                        expected=quantize565(pattern(((x-240)/2)*8,((y-180)/2)*8));
                    else if(x>=238 && x<402 && y>=178 && y<302) expected=24'hffffff;
                    else expected={2'b0,v[23:18],2'b0,v[15:10],2'b0,v[7:2]};
                    @(posedge clk);#1;
                    if(out!==expected || !dout || ho!==hs || vo!==vs)
                        $fatal(1,"pixel mode=%0d x=%0d y=%0d expected=%h actual=%h",mode,x,y,expected,out);
                    $fdisplay(fd,"%06h",out);
                end
                @(negedge clk);de=0;repeat(8) @(negedge clk);
            end
            $fclose(fd);
        end
    endtask
    initial begin
        $readmemh("fpga/src/user_source/hdl_source/boot_pic01.dath",boot);
        repeat(4) @(negedge clk);rst=0;repeat(3) @(negedge clk);
        check(!live,"no uninitialized SDRAM before first complete frame");
        check(active_width==0 && active_height==0,"boot has unknown TF dimensions");
        send(1);check(live && active_page==1 && ack==request && brightness==16,"first image commits without animation delay");
        check(active_width==640 && active_height==480,"first image metadata");
        // Simulate a failed or incomplete load: changing the header never issues a presentation request.
        source_width=123;source_height=456;repeat(3) next_frame();
        check(active_width==640 && active_height==480,"failed load preserves current dimensions");
        send(2);check(active_page==1 && brightness==16,"fade retains old image");
        for(integer i=15;i>=0;i--) begin next_frame();check(brightness==i && active_page==1,"fade-out progression");end
        next_frame();check(active_page==2 && brightness==0 && ack!=request,"bank switches at black frame");
        for(integer i=1;i<=16;i++) begin next_frame();check(brightness==i,"fade-in progression");end
        check(ack==request,"fade acknowledgment");
        for(integer q=5;q<=8;q++) begin
            send(q);check(wipe && boundary==0 && active_page==q,"question starts directional reveal");
            check(active_width==800 && active_height==600,"question dimensions commit with bank");
            for(integer n=1;n<16;n++) begin next_frame();check(wipe && boundary==n*40 && ack!=request,"wipe boundary/ACK");end
            next_frame();check(!wipe && ack==request,"question complete before reply");
            send(q+4);check(preview && active_page==q+4,"explanation preview");
            check(active_width==1024 && active_height==768,"explanation dimensions commit with bank");
            repeat(29) begin next_frame();check(preview && ack!=request,"hold thumbnail for 30 frames");end
            next_frame();check(!preview && ack==request,"full explanation before reply");
        end
        send(12);check(ack==request && !preview && !wipe,"same page no repeated animation");
        send(3);check(active_width==1024 && active_height==768,"fade-out retains old dimensions");
        repeat(16) next_frame();
        check(active_page==12 && active_width==1024,"zero-brightness old bank still has old size");
        next_frame();check(active_page==3 && active_width==640 && active_height==480,"fade black-frame metadata switch");
        repeat(16) next_frame();check(ack==request,"return to learning completes");
        @(negedge wclk);load_start=1;@(negedge wclk);load_start=0;
        for(integer y=0;y<480;y++) for(integer x=0;x<640;x++) begin
            pixel_write=1;load_rgb=pattern(x,479-y);@(negedge wclk);
        end
        pixel_write=0;
        render(0,"sim/render_boot.hex");render(1,"sim/render_fade.hex");
        render(2,"sim/render_wipe.hex");render(3,"sim/render_thumbnail.hex");
        $display("ALL PRESENTATION TESTS PASSED: first-frame boot, frame-boundary CDC/bank protection, fade, all question/answer transitions, 1228800 pixel comparisons and thumbnail orientation");
        passed=1;$finish;
    end
    initial begin #200000000;$fatal(1,"presentation watchdog");end
endmodule
