# Vivado synthesis comparison for controlled full poly_mul_top WL replacement.
# Usage:
#   vivado -mode batch -source scripts/run_synth_poly_compare.tcl -tclargs stageB xc7a200tsbg484-1 10.0
# Targets:
#   old    : all selectable Montgomery paths use old mont_mul, MUL_LAT=12
#   stageA : WL core BFU + INTT scale, old Pre_NTT/Pointwise/Post_INTT
#   stageB : stageA plus WL Pre_NTT u_pre_mul0/1
#   stageC : stageB plus WL Pointwise u_mul0/1, Post_INTT still old

set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ..]]
set report_dir [file join $repo_root reports]
file mkdir $report_dir

set_msg_config -id {Synth 8-7129} -limit 20

set target "stageB"
set part_name "xc7a200tsbg484-1"
set clock_period_ns 10.0
if {$argc >= 1} {
  set target [lindex $argv 0]
}
if {$argc >= 2} {
  set part_name [lindex $argv 1]
}
if {$argc >= 3} {
  set clock_period_ns [lindex $argv 2]
}

if {$target eq "old"} {
  set suffix "poly_mul_top_old"
  set generic_args [list MUL_LAT=12 USE_WL_MONT=0]
} elseif {$target eq "stageA"} {
  set suffix "poly_mul_top_stageA"
  set generic_args [list MUL_LAT=14 USE_WL_MONT=0 USE_WL_CORE=1 USE_WL_PRE_NTT=0]
} elseif {$target eq "stageB"} {
  set suffix "poly_mul_top_stageB"
  set generic_args [list MUL_LAT=14 USE_WL_MONT=1 USE_WL_CORE=1 USE_WL_PRE_NTT=1 USE_WL_POINTWISE=0]
} elseif {$target eq "stageC"} {
  set suffix "poly_mul_top_stageC"
  set generic_args [list MUL_LAT=14 USE_WL_MONT=1 USE_WL_CORE=1 USE_WL_PRE_NTT=1 USE_WL_POINTWISE=1]
} else {
  error "Unknown target '$target'. Use old, stageA, stageB, or stageC."
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

cd $repo_root
read_verilog -sv $rtl_files
puts "Synthesizing $target with generics: $generic_args"
synth_design -top poly_mul_top -part $part_name -generic $generic_args
create_clock -name clk -period $clock_period_ns [get_ports clk]

report_utilization -file [file join $report_dir "utilization_${suffix}.rpt"]
report_utilization -hierarchical -file [file join $report_dir "utilization_${suffix}_hier.rpt"]
report_timing_summary -file [file join $report_dir "timing_${suffix}.rpt"]
report_timing -max_paths 5 -sort_by group -file [file join $report_dir "timing_paths_${suffix}.rpt"]
report_power -file [file join $report_dir "power_${suffix}.rpt"]
write_checkpoint -force [file join $report_dir "${suffix}_synth.dcp"]
puts "Full poly_mul_top synthesis complete for $target. Reports written to $report_dir"
