set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ..]]
set report_dir [file join $repo_root reports]
file mkdir $report_dir
set_msg_config -id {Synth 8-7129} -limit 20
set part_name "xc7a200tsbg484-1"
set clock_period_ns 10.0
if {$argc >= 1} { set part_name [lindex $argv 0] }
if {$argc >= 2} { set clock_period_ns [lindex $argv 1] }
set rtl_files [list \
  rtl/params_pkg.sv \
  rtl/mod_add.sv \
  rtl/mod_sub.sv \
  rtl/delay_line.sv \
  rtl/delay_memory.sv \
  rtl/mont_mul.sv \
  rtl/gs_butterfly.sv \
  rtl/twiddle_rom.sv \
  rtl/mdc_stage.sv \
  rtl/gs_mdc_core.sv \
]
cd $repo_root
read_verilog -sv $rtl_files
synth_design -top gs_mdc_core -part $part_name
create_clock -name clk -period $clock_period_ns [get_ports clk]
report_utilization -file [file join $report_dir utilization_gs_mdc_core_only.rpt]
report_utilization -hierarchical -file [file join $report_dir utilization_gs_mdc_core_only_hier.rpt]
report_timing_summary -file [file join $report_dir timing_gs_mdc_core_only.rpt]
report_power -file [file join $report_dir power_gs_mdc_core_only.rpt]
write_checkpoint -force [file join $report_dir gs_mdc_core_only_synth.dcp]
puts "Core-only synthesis complete. Reports written to $report_dir"
