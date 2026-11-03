onerror {quit -f -code 1}
onbreak {resume}
vlib sim/sdram_clock_work
vmap sdram_clock sim/sdram_clock_work
vlog -work sdram_clock D:/Anlogic/TD_Release_2026.1_SP2/sim_release/eg4/eg_phy_pll.v
vlog -work sdram_clock +incdir+fpga/src/user_source/hdl_source/include +incdir+fpga/src/td_project fpga/src/user_source/hdl_source/IP/sys_pll.v fpga/src/user_source/hdl_source/include/sdr_init_ref.enc.v
vlog -sv -work sdram_clock sim/tb_sdram_clock_refresh.sv
vsim -voptargs=+acc -onfinish stop sdram_clock.tb_sdram_clock_refresh
run -all
if {[examine -radix unsigned /tb_sdram_clock_refresh/passed] != 1} {quit -f -code 1}
quit -f -code 0
