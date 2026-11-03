onerror {quit -f -code 1}
onbreak {resume}
if {![file exists sim/visual_work]} {vlib sim/visual_work}
vmap visual sim/visual_work
vlog -work visual D:/Anlogic/TD_Release_2026.1_SP2/sim_release/eg4/eg_logic_bram.v D:/Anlogic/TD_Release_2026.1_SP2/sim_release/eg4/eg_phy_bram.v D:/Anlogic/TD_Release_2026.1_SP2/sim_release/eg4/eg_phy_bram32k.v
vlog -sv -work visual fpga/src/user_source/hdl_source/audio_spectrum16.v fpga/src/user_source/hdl_source/audio_waveform_overlay.v fpga/src/user_source/hdl_source/quiz_feedback_subtitle.v fpga/src/user_source/hdl_source/hdmi_audio_tone_i2s_64fs.v fpga/src/user_source/hdl_source/I2S_receiver.v sim/tb_audio_spectrum.sv sim/tb_audio_waveform.sv sim/tb_quiz_feedback_subtitle.sv sim/tb_learning_ticker.sv sim/tb_audio_visualization.sv sim/tb_review_subtitle.sv
foreach name {tb_audio_spectrum tb_audio_waveform tb_quiz_feedback_subtitle tb_learning_ticker tb_audio_visualization tb_review_subtitle} {
    vsim -voptargs=+acc -onfinish stop visual.$name
    run -all
    if {[examine -radix unsigned /$name/passed] != 1} {quit -f -code 1}
    quit -sim
}
quit -f -code 0
