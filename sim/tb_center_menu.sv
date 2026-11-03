`timescale 1ns/1ps
module tb_center_menu;
    reg clk=0,rst=1,hs=1,vs=1,de=0,toggle=0;
    always #5 clk=~clk;
    reg [15:0] bundle=16'h8044;
    reg [10:0] width=640,height=480;
    wire ack,ho,vo,dout;
    wire [23:0] pixel;
    reg passed=0;
    reg [23:0] expected[0:307199];
    reg [15:0] fixtures[0:23];
    picture_osd dut(.clk(clk),.rst(rst),.hs(hs),.vs(vs),.de(de),.rgb(24'h123456),
        .settings_bundle(bundle),.settings_toggle(toggle),.settings_ack(ack),
        .source_width(width),.source_height(height),.hs_out(ho),.vs_out(vo),.de_out(dout),.rgb_out(pixel));
    task cycles(input integer n); repeat(n) @(negedge clk); endtask
    integer fd,changed;
    reg [15:0] snapshot;
    initial begin
        $readmemh("sim/center_menu_cases.mem",fixtures);
        cycles(4);rst=0;cycles(3);
        for(integer n=0;n<8;n++) begin
            $readmemh($sformatf("sim/center_menu_expected_%0d.hex",n),expected);
            snapshot=dut.active;
            bundle=fixtures[3*n];width=fixtures[3*n+1];height=fixtures[3*n+2];
            toggle=~toggle;cycles(5);
            if(dut.active!==snapshot) $fatal(1,"menu changed outside frame boundary");
            vs=0;cycles(2);vs=1;cycles(2);
            if(dut.active!==bundle || ack!==toggle) $fatal(1,"frame handshake failed");
            snapshot=bundle;
            fd=$fopen($sformatf("sim/center_menu_actual_%0d.hex",n),"w");
            changed=0;
            for(integer yy=0;yy<480;yy++) begin
                for(integer xx=0;xx<640;xx++) begin
                    @(negedge clk);de=1;
                    // Changing the menu while scanning must leave this complete frame intact.
                    if(n==3 && yy==240 && xx==0) begin bundle=16'h8044;toggle=~toggle;end
                    @(posedge clk);#1;
                    if(dut.active!==snapshot) $fatal(1,"torn frame n=%0d",n);
                    if(pixel!==expected[yy*640+xx]) $fatal(1,"OSD n=%0d x=%0d y=%0d got=%h expected=%h",n,xx,yy,pixel,expected[yy*640+xx]);
                    if(ho!==hs || vo!==vs || dout!==de) $fatal(1,"sync alignment");
                    if(pixel!=24'h123456) changed++;
                    $fdisplay(fd,"%06x",pixel);
                end
                @(negedge clk);de=0;cycles(2);
                if(pixel!==0 || dout!==0) $fatal(1,"blanking must be black");
            end
            $fclose(fd);
            if(changed==0) $fatal(1,"empty panel");
            // Acknowledge the pending mid-frame request before the next fixture.
            vs=0;cycles(2);vs=1;cycles(2);
        end
        rst=1;cycles(3);
        if(dut.active!==16'h8044 || ack!==0) $fatal(1,"reset defaults");
        $display("ALL CENTER MENU TESTS PASSED: 2457600 exact pixels, Chinese labels, 3 resolutions, all selections, values, frame atomicity, reset and blanking");
        passed=1;$finish;
    end
    initial begin #50000000;$fatal(1,"center menu watchdog");end
endmodule
