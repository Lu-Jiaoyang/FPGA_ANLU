`timescale 1ns/1ps
// The PLL vendor model is used; BUFG is a simulation-only ideal wire.
module EG_LOGIC_BUFG(input i, output o); assign o=i; endmodule
module tb_sdram_clock_refresh;
reg refclk=0, reset=1, init_reset=1;
always #10 refclk=~refclk;
wire c0,c1,c2,locked,done,req;
reg ack=0;
sys_pll pll(refclk,reset,c0,c1,c2,locked);
sdr_init_ref init_ref(.Sdr_clk(c1),.Rst(init_reset),.Sdr_init_req(1'b0),
 .Sdr_init_mode(4'b0011),.Sdr_init_done(done),.App_ref_req(1'b0),
 .Sdr_ref_req(req),.Sdr_ref_ack(ack),.Sdr_rw_vld(1'b0));
always @(posedge c1) ack<=req;
realtime t0,t1,p;
integer cycles=0,last_refresh=-1,requests=0;
reg passed=0;
always @(posedge c1) begin
 cycles=cycles+1;
 if(done && req) begin
  if(last_refresh>=0 && cycles-last_refresh!=1562)
   $fatal(1,"Refresh interval %0d expected 1562 clocks",cycles-last_refresh);
  last_refresh=cycles;
  requests=requests+1;
 end
end
initial begin
 #105 reset=0;
 wait(locked); repeat(4) @(negedge c1); init_reset=0; #10000;
 @(posedge c0); t0=$realtime; @(posedge c0); p=$realtime-t0;
 if(p<9.99 || p>10.01) $fatal(1,"C0 period %f",p);
 @(posedge c1); t0=$realtime; @(posedge c1); p=$realtime-t0;
 if(p<19.99 || p>20.01) $fatal(1,"C1 period %f",p);
 t0=$realtime; @(posedge c2); p=$realtime-t0;
 $display("SDRAM clock shift = %0.3f ns",p);
 if(p<6.99 || p>7.01) $fatal(1,"SDRAM phase %f expected 7ns",p);
 @(posedge c2); t0=$realtime; @(posedge c2); p=$realtime-t0;
 if(p<19.99 || p>20.01) $fatal(1,"C2 period %f",p);
 wait(done);
 if($realtime<200000) $fatal(1,"Power up shorter than 200us");
 wait(requests==8);
 passed=1;
 $display("PASS SDRAM clocks 100/50/50MHz, +7ns; 8 refresh requests spaced 31.24us");
 $finish;
end
initial begin #4000000; $fatal(1,"Clock/refresh timeout"); end
endmodule
