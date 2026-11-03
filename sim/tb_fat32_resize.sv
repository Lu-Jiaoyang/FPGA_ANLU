`timescale 1ns/1ps
module tb_fat32_resize;
    reg clk=0,rst=1,scan=0,load=0,ack=0;
    always #5 clk=~clk;
    reg [15:0] width=8,height=6;
    wire ready,scanned,done,err,fatal,req,pixel,sdreq,sdvalid,sdend,init;
    wire [7:0] code,sdbyte;
    wire [11:0] mask;
    wire [23:0] rgb;
    wire [31:0] lba;
    wire [10:0] source_width,source_height;
    integer count=0,tests=0,id=1;
    reg passed=0;
    fat32_bmp_reader #(.CLK_FREQ_HZ(100000000),.IO_TIMEOUT_MS(500)) dut(
        .clk(clk),.rst(rst),.sd_init_done(init),.scan_start(scan),.scan_done(scanned),
        .resource_valid(mask),.load_start(load),.load_index(4'(id-1)),.ready(ready),
        .load_done(done),.load_error(err),.error_code(code),.fatal_error(fatal),
        .source_width(source_width),.source_height(source_height),
        .bmp_width(width),.bmp_height(height),.write_req(req),.write_req_ack(ack),
        .sd_sec_read(sdreq),.sd_sec_read_addr(lba),.sd_sec_read_data(sdbyte),
        .sd_sec_read_data_valid(sdvalid),.sd_sec_read_end(sdend),.bmp_data_wr_en(pixel),.bmp_data(rgb));
    sd_card_top disk(.clk(clk),.rst(rst),.SD_MISO(1'b1),.sd_init_done(init),
        .sd_sec_read(sdreq),.sd_sec_read_addr(lba),.sd_sec_read_data(sdbyte),
        .sd_sec_read_data_valid(sdvalid),.sd_sec_read_end(sdend),.sd_sec_write(1'b0),
        .sd_sec_write_addr(32'd0),.sd_sec_write_data(8'd0),.SD_nCS(),.SD_DCLK(),.SD_MOSI(),
        .sd_sec_write_data_req(),.sd_sec_write_end());
    function automatic [23:0] expected(input integer n);
        integer x,y,p,v;
        begin
            x=(n%width)*disk.width/width;y=(n/width)*disk.height/height;
            p=y*disk.width+x;
            for(integer c=0;c<3;c++) begin
                v=int'(disk.pixel_byte(id,p*3+c));
                if(disk.width==2*width && disk.height==2*height)
                    v=(v+int'(disk.pixel_byte(id,(p+1)*3+c))+
                        int'(disk.pixel_byte(id,(p+disk.width)*3+c))+
                        int'(disk.pixel_byte(id,(p+disk.width+1)*3+c))+2)/4;
                expected[c*8+:8]=v;
            end
        end
    endfunction
    always @(posedge clk) ack<=!rst && req;
    always @(negedge clk) if(!rst) begin
        if(!$onehot(dut.state)) $fatal(1,"reader state not one hot");
        if(pixel) begin
            if(count>=width*height || rgb!==expected(count))
                $fatal(1,"FAT scaled pixel %0d got %h expected %h",count,rgb,expected(count));
            count=count+1;
        end
    end
    task image_case(input integer w,h,input [7:0] error_expected);
        integer ticks;
        begin
            @(negedge clk);rst=1;scan=0;load=0;
            disk.width=w;disk.height=h;count=0;
            repeat(5) @(negedge clk);rst=0;
            repeat(3) @(negedge clk);scan=1;@(negedge clk);scan=0;
            wait(scanned);if(mask!=4095 || code!=0) $fatal(1,"mount");
            @(negedge clk);load=1;@(negedge clk);load=0;ticks=0;
            while(!done && !err && ticks<100000000) begin @(negedge clk);ticks++;end
            if(code!=error_expected || (error_expected==0 ? !done || count!=width*height : !err || done))
                $fatal(1,"scaled completion w%0d h%0d count%0d code%h expected%h",w,h,count,code,error_expected);
            if(done && (source_width!=w || source_height!=h)) $fatal(1,"actual BMP header dimensions lost");
            tests++;$display("PASS FAT resize %0dx%0d -> %0dx%0d code %h",w,h,width,height,code);
        end
    endtask
    initial begin
        disk.continuous_bytes=1;
        image_case(1,1,0);image_case(3,5,0);image_case(7,9,0);image_case(16,12,0);
        image_case(8,6,0);image_case(19,13,0);id=12;image_case(31,17,0);
        image_case(0,2,8'h30);image_case(1921,1,8'h30);image_case(1,1081,8'h30);
        image_case(1,-1,8'h30);
        disk.truncated=12;image_case(3,5,8'h30);disk.truncated=0;
        disk.bad_header=12;image_case(16,12,8'h30);disk.bad_header=0;
        width=640;height=480;image_case(1,1,0);image_case(320,240,0);image_case(1280,960,0);
        image_case(1920,1080,0);
        image_case(640,480,0);image_case(800,600,0);image_case(1024,768,0);
        $display("ALL FAT32 RESIZE TESTS PASSED (%0d cases)",tests);passed=1;$finish;
    end
    initial begin #2000000000;$fatal(1,"FAT resize watchdog");end
endmodule
