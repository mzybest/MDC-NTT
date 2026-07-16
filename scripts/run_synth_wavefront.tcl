# Isolated 100 MHz synthesis for the mode-tagged dual-context wavefront top.
set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ..]]
set report_dir [file join $repo_root reports dual_context_wavefront synth]
file mkdir $report_dir

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
  rtl/intmul_64x64_24x17.sv \
  rtl/wlmont_round16.sv \
  rtl/mont_mul_wl.sv \
  rtl/mont_mul_select.sv \
  rtl/gs_butterfly.sv \
  rtl/twiddle_rom.sv \
  rtl/twiddle_rom_stage.sv \
  rtl/psi_rom.sv \
  rtl/mdc_reorder_context.sv \
  rtl/mdc_stage_dualctx.sv \
  rtl/gs_mdc_core_dualctx.sv \
  rtl/pointwise_mul.sv \
  rtl/poly_mul_top_wavefront.sv \
]

set generic_args [list \
  MUL_LAT=14 \
  USE_WL_MONT=1 \
  USE_WL_CORE=1 \
  USE_WL_PRE_NTT=1 \
  USE_WL_POINTWISE=1 \
  USE_WL_POST_INTT=1 \
  USE_STAGE_LOCAL_TWIDDLE=1 \
  TWIDDLE_BRAM_STAGES=4 \
]

cd $repo_root
set_msg_config -id {Synth 8-7129} -limit 20
read_verilog -sv $rtl_files
synth_design -top poly_mul_top_wavefront -part $part_name -generic $generic_args
create_clock -name clk -period $clock_period_ns [get_ports clk]

report_utilization -file [file join $report_dir utilization.rpt]
report_utilization -hierarchical -hierarchical_depth 7 \
  -file [file join $report_dir utilization_hierarchical.rpt]
catch {report_ram_utilization -file [file join $report_dir ram_utilization.rpt]}
report_timing_summary -file [file join $report_dir timing_summary.rpt]
report_timing -delay_type max -max_paths 10 -nworst 10 \
  -file [file join $report_dir timing_paths_top10.rpt]
report_power -file [file join $report_dir power.rpt]
write_checkpoint -force [file join $report_dir poly_mul_top_wavefront_synth.dcp]

set fd [open [file join $report_dir config.txt] w]
puts $fd "vivado=[version -short]"
puts $fd "part=$part_name"
puts $fd "period_ns=$clock_period_ns"
puts $fd "top=poly_mul_top_wavefront"
puts $fd "generics=$generic_args"
close $fd
puts "Dual-context wavefront synthesis complete: $report_dir"
exit 0
