onerror {quit -f -code 1}
onbreak {resume}
vlib sim/doc_fat32_resize
vmap doc_fat32_resize sim/doc_fat32_resize
vlog -work doc_fat32_resize D:/Anlogic/TD_Release_2026.1_SP2/sim_release/eg4/eg_logic_bram.v D:/Anlogic/TD_Release_2026.1_SP2/sim_release/eg4/eg_phy_bram.v D:/Anlogic/TD_Release_2026.1_SP2/sim_release/eg4/eg_phy_bram32k.v
vlog -sv -work doc_fat32_resize fpga/src/user_source/hdl_source/SD/fat32_bmp_reader.v fpga/src/user_source/hdl_source/SD/bmp_resize_stream.v
vlog -sv -work doc_fat32_resize sim/sd_card_model.sv sim/tb_fat32.sv
vlog -sv -work doc_fat32_resize sim/tb_fat32_resize.sv
vsim -novopt -onfinish stop doc_fat32_resize.tb_fat32_resize
run -all
if {[examine -radix unsigned /tb_fat32_resize/passed] != 1} {quit -f -code 1}
quit -f -code 0
