onerror {quit -f -code 1}
onbreak {resume}
if {![file exists sim/center_menu_work]} {vlib sim/center_menu_work}
vmap center_menu sim/center_menu_work
vlog -sv -work center_menu fpga/src/user_source/hdl_source/picture_osd.v sim/tb_center_menu.sv
vsim -voptargs=+acc -onfinish stop center_menu.tb_center_menu
run -all
if {[examine -radix unsigned /tb_center_menu/passed] != 1} {quit -f -code 1}
quit -f -code 0
