onerror {quit -f -code 1}
onbreak {resume}
if {![file exists sim/work]} {vlib sim/work}
vmap single sim/work
vlog -sv -work single common/key_debounce.v common/score_digits.v common/seg_scan8.v common/uart_tx.v common/single_board_control.v interaction/rtl/quiz_answer_session.v interaction/rtl/quiz_answer_display.v interaction/rtl/quiz_pc_reporter.v interaction/rtl/key_beep.v fpga/src/user_source/hdl_source/quiz_presentation_session.v fpga/src/user_source/hdl_source/quiz_presentation_display.v fpga/src/user_source/hdl_source/picture_controls.v fpga/src/user_source/hdl_source/SD/sd_card_bmp.v sim/tb_single_board.sv
vsim -voptargs=+acc -onfinish stop single.tb_single_board
run -all
if {[examine -radix unsigned /tb_single_board/passed] != 1} {quit -f -code 1}
quit -f -code 0
