# Vivado implementation script for the optimized baseline.
# Run from the repository root:
#   vivado -mode batch -source scripts/run_impl.tcl
# Optional overrides:
#   vivado -mode batch -source scripts/run_impl.tcl -tclargs xc7a200tsbg484-1 12.0

set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ..]]
set report_dir [file join $repo_root reports]
file mkdir $report_dir

# Avoid flooding older Vivado builds with one warning per trimmed placeholder
# bit while preserving a representative sample in vivado.log.
set_msg_config -id {Synth 8-7129} -limit 20

set part_name "xc7a200tsbg484-1"
set clock_period_ns 12.0
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
  rtl/gs_butterfly.sv \
  rtl/twiddle_rom.sv \
  rtl/psi_rom.sv \
  rtl/mdc_stage.sv \
  rtl/gs_mdc_core.sv \
  rtl/dual_port_ram.sv \
  rtl/pointwise_mul.sv \
  rtl/poly_mul_top.sv \
]

cd $repo_root
read_verilog -sv $rtl_files
synth_design -top poly_mul_top -part $part_name
create_clock -name clk -period $clock_period_ns [get_ports clk]

opt_design
write_checkpoint -force [file join $report_dir poly_mul_top_impl_12ns_opt.dcp]

place_design
write_checkpoint -force [file join $report_dir poly_mul_top_impl_12ns_placed.dcp]

route_design
write_checkpoint -force [file join $report_dir poly_mul_top_impl_12ns_routed.dcp]

report_utilization -file [file join $report_dir impl_12ns_utilization.rpt]
report_timing_summary -file [file join $report_dir impl_12ns_timing.rpt]
report_power -file [file join $report_dir impl_12ns_power.rpt]

puts "Implementation complete. Reports written to $report_dir"
