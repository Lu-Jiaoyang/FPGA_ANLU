onerror {quit -f -code 1}
onbreak {resume}
if {![file exists sim/media_work]} {vlib sim/media_work}
vmap media sim/media_work
vlog -work media D:/Anlogic/TD_Release_2026.1_SP2/sim_release/eg4/eg_logic_bram.v D:/Anlogic/TD_Release_2026.1_SP2/sim_release/eg4/eg_phy_bram.v D:/Anlogic/TD_Release_2026.1_SP2/sim_release/eg4/eg_phy_bram32k.v
vlog -sv -work media fpga/src/user_source/hdl_source/SD/sd_card_bmp.v fpga/src/user_source/hdl_source/SD/fat32_bmp_reader.v fpga/src/user_source/hdl_source/SD/bmp_resize_stream.v fpga/src/user_source/hdl_source/SD/sd_card_top.v fpga/src/user_source/hdl_source/SD/sd_card_cmd.v fpga/src/user_source/hdl_source/SD/sd_card_sec_read_write.v fpga/src/user_source/hdl_source/SD/spi_master.v fpga/src/user_source/hdl_source/picture_osd.v fpga/src/user_source/hdl_source/hdmi_audio_tone_i2s_64fs.v sim/tb_learning_media.sv
vsim -voptargs=+acc -onfinish stop media.tb_learning_media
run -all
if {[examine -radix unsigned /tb_learning_media/passed] != 1} {quit -f -code 1}
quit -f -code 0
