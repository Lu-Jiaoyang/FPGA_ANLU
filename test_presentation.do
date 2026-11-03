onerror {quit -f -code 1}
onbreak {resume}
vlib sim/doc_presentation
vmap doc_presentation sim/doc_presentation
vlog -work doc_presentation D:/Anlogic/TD_Release_2026.1_SP2/sim_release/eg4/eg_logic_bram.v D:/Anlogic/TD_Release_2026.1_SP2/sim_release/eg4/eg_phy_bram.v D:/Anlogic/TD_Release_2026.1_SP2/sim_release/eg4/eg_phy_bram32k.v
vlog -sv -work doc_presentation fpga/src/user_source/hdl_source/image_present_control.v fpga/src/user_source/hdl_source/quiz_video_effects.v fpga/src/user_source/hdl_source/picture_tone.v
vlog -sv -work doc_presentation sim/tb_presentation.sv
vsim -novopt -onfinish stop doc_presentation.tb_presentation
vcd file sim/presentation.vcd
vcd add /tb_presentation/clk /tb_presentation/rst /tb_presentation/frame /tb_presentation/request /tb_presentation/ack /tb_presentation/active_bank /tb_presentation/active_page /tb_presentation/brightness /tb_presentation/wipe /tb_presentation/preview /tb_presentation/boundary /tb_presentation/active_width /tb_presentation/active_height
run -all
if {[examine -radix unsigned /tb_presentation/passed] != 1} {quit -f -code 1}
quit -f -code 0
