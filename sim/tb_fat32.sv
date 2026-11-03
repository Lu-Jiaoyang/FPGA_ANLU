`timescale 1ns/1ps
module tb_fat32;
    reg clk=0, rst=1, scan=0, load=0, ack=0;
    reg [3:0] index=0;
    reg [15:0] width=640,height=480;
    wire ready,scan_done,done,err,fatal,req,pixel,sdreq,sdvalid,sdend,init;
    wire [7:0] code,sdbyte;
    wire [11:0] mask;
    wire [23:0] rgb;
    wire [31:0] lba;
    integer count=0, expected_id=1, ack_delay=0, tests=0;
    reg pixel_check=1;
    reg passed=0;
    always #5 clk=~clk;
    always @(negedge clk) if(!rst && !$onehot(dut.state))
        $fatal(1,"Reader state must be one-hot for parallel synthesis decode");
    fat32_bmp_reader #(.CLK_FREQ_HZ(1000000),.IO_TIMEOUT_MS(10),.MAX_DIR_CLUSTERS(8)) dut(
        .clk(clk),.rst(rst),.sd_init_done(init),.scan_start(scan),.scan_done(scan_done),
        .resource_valid(mask),.load_start(load),.load_index(index),.ready(ready),
        .load_done(done),.load_error(err),.error_code(code),.fatal_error(fatal),
        .bmp_width(width),.bmp_height(height),.write_req(req),.write_req_ack(ack),
        .sd_sec_read(sdreq),.sd_sec_read_addr(lba),.sd_sec_read_data(sdbyte),
        .sd_sec_read_data_valid(sdvalid),.sd_sec_read_end(sdend),.bmp_data_wr_en(pixel),.bmp_data(rgb));
    sd_card_top disk(.clk(clk),.rst(rst),.SD_MISO(1'b1),.sd_init_done(init),
        .sd_sec_read(sdreq),.sd_sec_read_addr(lba),.sd_sec_read_data(sdbyte),
        .sd_sec_read_data_valid(sdvalid),.sd_sec_read_end(sdend),.sd_sec_write(1'b0),
        .sd_sec_write_addr(32'd0),.sd_sec_write_data(8'd0),.SD_nCS(),.SD_DCLK(),.SD_MOSI(),
        .sd_sec_write_data_req(),.sd_sec_write_end());
    always @(posedge clk) begin
        if(rst) begin ack<=0; ack_delay<=0; end
        else if(req) begin
            if(ack_delay==4) ack<=1; else ack_delay<=ack_delay+1;
        end else begin ack<=0; ack_delay<=0; end
        if(pixel) begin
            if(pixel_check && rgb !== {disk.pixel_byte(expected_id,count*3+2),
                                      disk.pixel_byte(expected_id,count*3+1),disk.pixel_byte(expected_id,count*3)})
                $fatal(1,"RGB mismatch pixel %0d id %0d: %h",count,expected_id,rgb);
            count=count+1;
        end
    end
    task check(input bit ok,input string msg);
        if(!ok) $fatal(1,"FAIL %s, code=%h state=%0d",msg,code,dut.state);
    endtask
    task reset_disk;
        begin
            @(negedge clk); rst=1; scan=0; load=0; count=0;
            repeat(5) @(negedge clk); rst=0; repeat(2) @(negedge clk);
        end
    endtask
    task mount(input [11:0] expected_mask,input [7:0] expected_code);
        integer t;
        begin
            @(negedge clk); scan=1; @(negedge clk); scan=0;
            t=0;
            while(!scan_done && t<100000) begin @(negedge clk); t=t+1; end
            check(scan_done && mask==expected_mask && code==expected_code,"mount result");
            tests=tests+1;
        end
    endtask
    task read_image(input integer id,input [7:0] expected_code);
        integer t;
        begin
            @(negedge clk); count=0; expected_id=id; index=id-1; load=1;
            @(negedge clk); load=0; t=0;
            while(!done && !err && t<5000000) begin @(negedge clk); t=t+1; end
            check(t<5000000 && code==expected_code,"file completion/code");
            if(expected_code==0) check(done && count==width*height,"complete image pixel count");
            else check(err && !done,"failed image is not successful");
            tests=tests+1;
        end
    endtask
    initial begin
        reset_disk(); mount(4095,0);
        for(integer id=1;id<=12;id=id+1) read_image(id,0);
        $display("PASS full-size fragmented RGB24 images, MBR third entry, multi-cluster directory");
        width=4; height=2; disk.width=4; disk.height=2;
        // Directory commits must also work when the next byte arrives without an idle cycle.
        disk.continuous_bytes=1;
        reset_disk(); mount(4095,0);
        for(integer id=1;id<=12;id=id+1) read_image(id,0);
        disk.duplicate=1; reset_disk(); mount(0,8'h14);
        disk.duplicate=0; disk.continuous_bytes=0;
        $display("PASS continuous directory bytes, twelve committed slots, and duplicate rejection");
        disk.partition=0; disk.active_fat=1;
        reset_disk(); mount(4095,0); read_image(2,0);
        disk.spc=4; reset_disk(); mount(4095,0); read_image(4,0);
        disk.spc=128; reset_disk(); mount(4095,0); read_image(3,0);
        disk.spc=64; reset_disk(); mount(4095,0); read_image(12,0);
        disk.spc=2;
        disk.missing=10; reset_disk(); mount(3583,0); read_image(10,8'h15); read_image(11,0);
        disk.missing=0; reset_disk(); mount(4095,0); read_image(13,8'h15); read_image(16,8'h15);
        disk.missing=2; reset_disk(); mount(4093,0); read_image(2,8'h15); read_image(3,0);
        disk.missing=0; disk.bad_header=1; reset_disk(); mount(4095,0); read_image(1,8'h30); read_image(4,0);
        disk.bad_header=0; disk.truncated=3; reset_disk(); mount(4095,0); read_image(3,8'h30);
        disk.truncated=0; disk.duplicate=1; reset_disk(); mount(0,8'h14);
        disk.duplicate=0; disk.bad_bpb=1; reset_disk(); mount(0,8'h12);
        disk.bad_bpb=0; disk.short_sector=1; reset_disk(); mount(0,8'h11); check(fatal,"short read quarantine");
        disk.short_sector=0; disk.extra_sector=1; reset_disk(); mount(0,8'h11); check(fatal,"extra byte with end quarantine");
        disk.extra_sector=0; disk.stall=1; reset_disk(); mount(0,8'h10); check(fatal,"timeout quarantine");
        disk.stall=0; disk.missing=2; disk.dir_loop=1; reset_disk(); mount(0,8'h14);
        disk.dir_loop=0; disk.missing=0; width=640; height=480; disk.width=640; disk.height=480;
        disk.early_eof=1; reset_disk(); mount(4095,0); read_image(1,8'h22);
        disk.early_eof=0; disk.chain_loop=1; pixel_check=0;
        reset_disk(); mount(4095,0); read_image(1,8'h21);
        disk.chain_loop=0; pixel_check=1;
        reset_disk(); mount(4095,0);
        @(negedge clk); index=0; load=1; @(negedge clk); load=0;
        repeat(2500) @(negedge clk);
        reset_disk(); mount(4095,0); read_image(1,0);
        $display("ALL FAT32 TESTS PASSED (%0d checks)",tests); passed=1; $finish;
    end
    initial begin #1200000000; $fatal(1,"watchdog"); end
endmodule
