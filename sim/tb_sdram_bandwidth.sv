`timescale 1ns/1ps
// Exercises the real controller and FIFO IP. DQ is deliberately unmodelled:
// this checks service rate and under/overflow, not stored pixel correctness.
module tb_sdram_bandwidth;
reg mclk=0,pclk=0,wclk=0,sclk=0,rst=1;
always #10 mclk=~mclk;
always #20 pclk=~pclk;
always #5 wclk=~wclk;
initial begin #7; forever #10 sclk=~sclk; end
wire init_done,ref_vld,busy,rd_en,wr_en,rd_valid;
wire [20:0] rd_addr,wr_addr;
wire [31:0] wr_data,rd_data,pixel;
wire [3:0] dm;
reg read_req=0,read_en=0,write_req=0,write_en=0;
reg [31:0] write_data=0;
wire read_ack,write_ack,read_finish,write_finish;
wire sdram_clk,ras,cas,we;
wire [1:0] ba;
wire [10:0] addr;
wire [3:0] sdm;
wire [31:0] dq;
integer consumed=0,returned=0,written=0,refreshes=0;
reg passed=0,writer_done=0;
sdr_as_ram ctrl(.Sdr_clk(mclk),.Sdr_clk_sft(sclk),.Rst(rst),
 .Sdr_init_done(init_done),.Sdr_init_ref_vld(ref_vld),.Sdr_busy(busy),
 .App_ref_req(1'b0),.App_wr_en(wr_en),.App_wr_addr(wr_addr),.App_wr_dm(dm),
 .App_wr_din(wr_data),.App_rd_en(rd_en),.App_rd_addr(rd_addr),
 .Sdr_rd_en(rd_valid),.Sdr_rd_dout(rd_data),.SDRAM_CLK(sdram_clk),
 .SDR_RAS(ras),.SDR_CAS(cas),.SDR_WE(we),.SDR_BA(ba),.SDR_ADDR(addr),.SDR_DM(sdm),.SDR_DQ(dq));
frame_read_write frame(.rst(rst),.mem_clk(mclk),.Sdr_init_done(init_done),
 .Sdr_init_ref_vld(ref_vld),.Sdr_busy(busy),.App_rd_en(rd_en),.App_rd_addr(rd_addr),
 .Sdr_rd_en(rd_valid),.Sdr_rd_dout(rd_data),.read_clk(pclk),.read_req(read_req),
 .read_req_ack(read_ack),.read_finish(read_finish),.read_addr_0(21'd0),.read_addr_1(21'd0),
 .read_addr_2(21'd0),.read_addr_3(21'd0),.read_addr_index(2'd0),.read_len(21'd307200),
 .read_en(read_en),.read_data(pixel),.App_wr_en(wr_en),.App_wr_addr(wr_addr),
 .App_wr_din(wr_data),.App_wr_dm(dm),.write_clk(wclk),.write_req(write_req),
 .write_req_ack(write_ack),.write_finish(write_finish),.write_addr_0(21'd524288),
 .write_addr_1(21'd524288),.write_addr_2(21'd524288),.write_addr_3(21'd524288),
 .write_addr_index(2'd0),.write_len(21'd307200),.write_en(write_en),.write_data(write_data));
always @(posedge pclk) if(!rst && read_en) begin
 if(frame.read_buf.empty_flag !== 1'b0) $fatal(1,"Pixel FIFO underrun pixel=%0d time=%t",consumed,$time);
 consumed=consumed+1;
end
always @(posedge wclk) if(!rst && write_en && frame.write_buf.full_flag !== 1'b0)
 $fatal(1,"Write FIFO overflow state=%0d used=%b port=%b into=%b rd_busy=%b rd_state=%0d returned=%0d written=%0d",frame.frame_fifo_write_m0.state,frame.rdusedw,frame.frame_fifo_write_m0.rdusedw,frame.frame_fifo_write_m0.into_burst,frame.O_rd_busy,frame.frame_fifo_read_m0.state,returned,written);
always @(posedge mclk) if(!rst) begin
 if(rd_valid) begin
  if(frame.read_buf.full_flag !== 1'b0) $fatal(1,"Read FIFO overflow");
  returned=returned+1;
 end
 if(wr_en) written=written+1;
end
always @(posedge sdram_clk) if(init_done && {ras,cas,we}===3'b001) refreshes=refreshes+1;
initial begin
 #105 rst=0;
 wait(init_done);
 repeat(3) begin
  @(negedge pclk); read_req=1;
  wait(read_ack); @(negedge pclk); read_req=0;
  repeat(1600) @(negedge pclk);
  repeat(480) begin
   repeat(640) begin read_en=1; @(negedge pclk); end
   read_en=0;
   repeat(160) @(negedge pclk);
  end
  repeat(34400) @(negedge pclk);
 end
 wait(writer_done);
 if(consumed!=921600 || written!=307200 || refreshes<500)
  $fatal(1,"Unexpected totals read=%0d write=%0d refresh=%0d",consumed,written,refreshes);
 passed=1;
 $display("PASS SDRAM bandwidth: %0d pixels, %0d concurrent writes, %0d refresh commands; no FIFO under/overflow",consumed,written,refreshes);
 $finish;
end
initial begin
 wait(init_done);
 @(negedge wclk); write_req=1;
 wait(write_ack); @(negedge wclk); write_req=0;
 repeat(10) @(negedge wclk);
 repeat(307200) begin
  write_en=1; write_data=write_data+1;
  @(negedge wclk); write_en=0;
  repeat(9) @(negedge wclk);
 end
 wait(write_finish); writer_done=1;
end
initial begin #65000000; $fatal(1,"Bandwidth timeout"); end
endmodule
