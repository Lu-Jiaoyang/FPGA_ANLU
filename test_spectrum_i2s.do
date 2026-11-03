onerror {quit -f -code 1}
onbreak {resume}
vmap visual sim/visual_work
vlog -sv -work visual sim/tb_audio_visualization.sv
vsim -voptargs=+acc -onfinish stop visual.tb_audio_visualization
run -all
if {[examine -radix unsigned /tb_audio_visualization/passed] != 1} {quit -f -code 1}
quit -f -code 0
