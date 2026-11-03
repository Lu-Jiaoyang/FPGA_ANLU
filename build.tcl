cd {C:/Users/lenovo/Downloads/FPGA_submission_20261031_final/science_learning_system/fpga/src/td_project}
if {[catch {source {D:/Anlogic/TD_Release_2026.1_SP2/scripts/DefaultFlow.tcl}} result]} {
    puts stderr $result
    exit 1
}
report_timing_summary -file final_timing.rpt
write_verilog single_board_quiz_routed.v
exit 0
