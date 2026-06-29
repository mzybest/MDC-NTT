# Synthesize either the active Montgomery multiplier or the experimental
# word-level Montgomery multiplier as a standalone top.
#
# Usage:
#   vivado -mode batch -source scripts/run_synth_mont_compare.tcl \
#     -tclargs current xc7a200tsbg484-1 10.0
#   vivado -mode batch -source scripts/run_synth_mont_compare.tcl \
#     -tclargs wl xc7a200tsbg484-1 10.0

set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ..]]
set report_dir [file join $repo_root reports]
file mkdir $report_dir

set target "wl"
set part_name "xc7a200tsbg484-1"
set clock_period_ns 10.0

if {$argc >= 1} { set target [lindex $argv 0] }
if {$argc >= 2} { set part_name [lindex $argv 1] }
if {$argc >= 3} { set clock_period_ns [lindex $argv 2] }

cd $repo_root

if {$target eq "current"} {
  set top_name "mont_mul"
  set suffix "mont_mul_current"
  set rtl_files [list rtl/params_pkg.sv rtl/mont_mul.sv]
} elseif {$target eq "wl"} {
  set top_name "mont_mul_wl"
  set suffix "mont_mul_wl"
  set rtl_files [list \
    rtl/params_pkg.sv \
    rtl/intmul_64x64_24x17.sv \
    rtl/wlmont_round16.sv \
    rtl/mont_mul_wl.sv \
  ]
} else {
  error "Unknown target '$target'. Use 'current' or 'wl'."
}

read_verilog -sv $rtl_files
synth_design -top $top_name -part $part_name
create_clock -name clk -period $clock_period_ns [get_ports clk]

report_utilization -file [file join $report_dir "utilization_${suffix}.rpt"]
report_utilization -hierarchical -file [file join $report_dir "utilization_${suffix}_hier.rpt"]
report_timing_summary -file [file join $report_dir "timing_${suffix}.rpt"]
report_power -file [file join $report_dir "power_${suffix}.rpt"]
write_checkpoint -force [file join $report_dir "${suffix}_synth.dcp"]

puts "Standalone synthesis complete for $top_name. Reports written to $report_dir"
