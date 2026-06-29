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

if {$target eq "old"} {
  set suffix "gs_mdc_core_old"
  set generic_args [list MUL_LAT=12 USE_WL_MONT=0]
} elseif {$target eq "wl"} {
  set suffix "gs_mdc_core_wl"
  set generic_args [list MUL_LAT=14 USE_WL_MONT=1]
} else {
  error "Unknown target '$target'. Use old or wl."
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
  rtl/mdc_stage.sv \
  rtl/gs_mdc_core.sv \
]

cd $repo_root
read_verilog -sv $rtl_files
synth_design -top gs_mdc_core -part $part_name -generic $generic_args
create_clock -name clk -period $clock_period_ns [get_ports clk]
report_utilization -file [file join $report_dir "utilization_${suffix}.rpt"]
report_utilization -hierarchical -file [file join $report_dir "utilization_${suffix}_hier.rpt"]
report_timing_summary -file [file join $report_dir "timing_${suffix}.rpt"]
report_power -file [file join $report_dir "power_${suffix}.rpt"]
write_checkpoint -force [file join $report_dir "${suffix}_synth.dcp"]
puts "Core synthesis complete for $target. Reports written to $report_dir"

