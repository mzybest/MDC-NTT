# Vivado synthesis script for the explicit Pre/Post negacyclic baseline.
# Run from the repository root:
#   vivado -mode batch -source scripts/run_synth.tcl

set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ..]]
set report_dir [file join $repo_root reports]
file mkdir $report_dir

# Avoid flooding older Vivado builds with one warning per trimmed placeholder
# bit while preserving a representative sample in vivado.log.
set_msg_config -id {Synth 8-7129} -limit 20

# Override from the command line when targeting a different FPGA:
#   vivado -mode batch -source scripts/run_synth.tcl -tclargs xc7a200tsbg484-1 10.0
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

report_utilization -file [file join $report_dir utilization.rpt]
report_timing_summary -file [file join $report_dir timing_summary.rpt]
report_power -file [file join $report_dir power.rpt]

write_checkpoint -force [file join $report_dir poly_mul_top_synth.dcp]
puts "Synthesis complete. Reports written to $report_dir"
