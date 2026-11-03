onerror {quit -f -code 1}
onbreak {resume}
vlib sim/pc_work
vmap pc sim/pc_work
vlog -sv -work pc common/uart_tx.v interaction/rtl/quiz_pc_reporter.v sim/tb_pc_reporter.sv
vsim -onfinish stop pc.tb_pc_reporter
run -all
if {[examine -radix unsigned /tb_pc_reporter/passed] != 1} {quit -f -code 1}
quit -f -code 0
