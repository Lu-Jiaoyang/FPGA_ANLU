onerror {quit -f -code 1}
onbreak {resume}
if {![file exists sim/answer_audio_work]} {vlib sim/answer_audio_work}
vmap answer_audio sim/answer_audio_work
vlog -work answer_audio D:/Anlogic/TD_Release_2026.1_SP2/sim_release/eg4/eg_logic_bram.v D:/Anlogic/TD_Release_2026.1_SP2/sim_release/eg4/eg_phy_bram.v D:/Anlogic/TD_Release_2026.1_SP2/sim_release/eg4/eg_phy_bram32k.v
vlog -sv -work answer_audio sim/tb_answer_recordings.sv fpga/src/user_source/hdl_source/I2S_receiver.v fpga/src/user_source/hdl_source/hdmi_audio_tone_i2s_64fs.v
vsim -voptargs=+acc -onfinish stop answer_audio.tb_answer_recordings
run -all
if {[examine -radix unsigned /tb_answer_recordings/passed] != 1} {quit -f -code 1}
quit -f -code 0
