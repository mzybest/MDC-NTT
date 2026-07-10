# Vivado post-route implementation for Stage D full WL poly_mul_top.
# Usage:
#   vivado -mode batch -source scripts/run_impl_poly_stageD.tcl -tclargs xc7a200tsbg484-1 10.0

set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ..]]
set report_dir [file join $repo_root reports]
file mkdir $report_dir

set_msg_config -id {Synth 8-7129} -limit 20

set part_name "xc7a200tsbg484-1"
set clock_period_ns 10.0
if {$argc >= 1} {
  set part_name [lindex $argv 0]
}
if {$argc >= 2} {
  set clock_period_ns [lindex $argv 1]
}

set rtl_files [list \
  rtl/params_pkg.sv \
  rtl/mod_add.sv \
  rtl/mod_sub.sv \
  rtl/delay_line.sv \
  rtl/delay_memory.sv \
  rtl/mont_mul.sv \
  rtl/intmul_64x64_24x17.sv \
  rtl/wlmont_round16.sv \
  rtl/mont_mul_wl.sv \
  rtl/mont_mul_select.sv \
  rtl/gs_butterfly.sv \
  rtl/twiddle_rom.sv \
  rtl/psi_rom.sv \
  rtl/mdc_stage.sv \
  rtl/gs_mdc_core.sv \
  rtl/dual_port_ram.sv \
  rtl/pointwise_mul.sv \
  rtl/poly_mul_top.sv \
]

set generic_args [list \
  MUL_LAT=14 \
  USE_WL_MONT=1 \
  USE_WL_CORE=1 \
  USE_WL_PRE_NTT=1 \
  USE_WL_POINTWISE=1 \
  USE_WL_POST_INTT=1 \
]

cd $repo_root
read_verilog -sv $rtl_files
puts "Implementing Stage D full WL with generics: $generic_args"
synth_design -top poly_mul_top -part $part_name -generic $generic_args
create_clock -name clk -period $clock_period_ns [get_ports clk]

opt_design
write_checkpoint -force [file join $report_dir "impl_poly_mul_top_stageD_100mhz_opt.dcp"]

place_design
write_checkpoint -force [file join $report_dir "impl_poly_mul_top_stageD_100mhz_placed.dcp"]

phys_opt_design
write_checkpoint -force [file join $report_dir "impl_poly_mul_top_stageD_100mhz_physopt.dcp"]

route_design
write_checkpoint -force [file join $report_dir "impl_poly_mul_top_stageD_100mhz_routed.dcp"]

report_utilization -file [file join $report_dir "impl_utilization_poly_mul_top_stageD_100mhz.rpt"]
report_timing_summary -file [file join $report_dir "impl_timing_poly_mul_top_stageD_100mhz.rpt"]
report_timing -max_paths 10 -sort_by group -file [file join $report_dir "impl_timing_paths_poly_mul_top_stageD_100mhz.rpt"]
report_power -file [file join $report_dir "impl_power_poly_mul_top_stageD_100mhz.rpt"]

puts "Stage D implementation complete. Reports written to $report_dir"
