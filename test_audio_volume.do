onerror {quit -f -code 1}
onbreak {resume}
if {![file exists sim/volume_work]} {vlib sim/volume_work}
vmap volume sim/volume_work
vlog -sv -work volume fpga/src/user_source/hdl_source/audio_volume.v fpga/src/user_source/hdl_source/audio_spectrum16.v fpga/src/user_source/hdl_source/audio_waveform_overlay.v sim/tb_audio_volume.sv
vsim -voptargs=+acc -onfinish stop volume.tb_audio_volume
run -all
if {[examine -radix unsigned /tb_audio_volume/passed] != 1} {quit -f -code 1}
quit -f -code 0
