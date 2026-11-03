onerror {quit -f -code 1}
onbreak {resume}
vlib sim/sdram_bw_work
vmap sdram_bw sim/sdram_bw_work
vlog -work sdram_bw D:/Anlogic/TD_Release_2026.1_SP2/sim_release/eg4/eg_logic_bram.v D:/Anlogic/TD_Release_2026.1_SP2/sim_release/eg4/eg_phy_bram.v
vlog -work sdram_bw +incdir+fpga/src/user_source/hdl_source/include +incdir+fpga/src/td_project fpga/src/user_source/hdl_source/include/sdr_as_ram.enc.v fpga/src/user_source/hdl_source/include/sdr_wrrd.enc.v fpga/src/user_source/hdl_source/include/sdr_init_ref.enc.v fpga/src/user_source/hdl_source/IP/afifo_16_32_256.v fpga/src/user_source/hdl_source/IP/afifo_32_16_256.v fpga/src/user_source/hdl_source/SD/frame_read_write.v fpga/src/user_source/hdl_source/SD/frame_fifo_read.v fpga/src/user_source/hdl_source/SD/frame_fifo_write.v
vlog -sv -work sdram_bw sim/tb_sdram_bandwidth.sv
vsim -voptargs=+acc -onfinish stop sdram_bw.tb_sdram_bandwidth
run -all
if {[examine -radix unsigned /tb_sdram_bandwidth/passed] != 1} {quit -f -code 1}
quit -f -code 0
