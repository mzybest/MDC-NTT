# Isolated synthesis for dual-forward DSP-reduction configurations.
set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ..]]

if {$argc < 4} {
  error "Usage: <config> <part> <period_ns> <report_subdir>"
}

set config [lindex $argv 0]
set part_name [lindex $argv 1]
set clock_period_ns [lindex $argv 2]
set report_subdir [lindex $argv 3]
set report_dir [file join $repo_root reports dual_forward_dsp_reduction $report_subdir]
file mkdir $report_dir

set use_load_preprocess 0
set fuse_intt_scale_in_post 0
set use_final_unit_twiddle_bypass 0
set use_top_data_bram 0
set use_shared_periph_mont 0
set use_natural_ab_loader 0
switch -- $config {
  baseline { }
  load_pre { set use_load_preprocess 1 }
  fused_post { set fuse_intt_scale_in_post 1 }
  combined {
    set use_load_preprocess 1
    set fuse_intt_scale_in_post 1
  }
  combined_unit_twiddle {
    set use_load_preprocess 1
    set fuse_intt_scale_in_post 1
    set use_final_unit_twiddle_bypass 1
  }
  bram_raw_pre {
    set fuse_intt_scale_in_post 1
    set use_final_unit_twiddle_bypass 1
    set use_top_data_bram 1
  }
  bram_raw_pre_shared {
    set fuse_intt_scale_in_post 1
    set use_final_unit_twiddle_bypass 1
    set use_top_data_bram 1
    set use_shared_periph_mont 1
  }
  natural_ab_raw_pre_shared {
    set fuse_intt_scale_in_post 1
    set use_final_unit_twiddle_bypass 1
    set use_top_data_bram 1
    set use_shared_periph_mont 1
    set use_natural_ab_loader 1
  }
  default { error "Unknown DSP-reduction configuration: $config" }
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
  rtl/peripheral_mont_pool.sv \
  rtl/gs_butterfly.sv \
  rtl/twiddle_rom.sv \
  rtl/twiddle_rom_stage.sv \
  rtl/twiddle_rom_stage_ntt.sv \
  rtl/psi_rom.sv \
  rtl/psi_post_rom.sv \
  rtl/mdc_stage.sv \
  rtl/gs_mdc_core.sv \
  rtl/gs_mdc_core_ntt_only.sv \
  rtl/pointwise_mul.sv \
  rtl/top_data_bram.sv \
  rtl/poly_mul_top_dual_forward.sv \
]

set generic_args [list \
  MUL_LAT=14 \
  USE_WL_MONT=1 \
  USE_WL_CORE=1 \
  USE_WL_PRE_NTT=1 \
  USE_WL_POINTWISE=1 \
  USE_WL_POST_INTT=1 \
  USE_BFU_BOUNDARY_PIPE=1 \
  USE_STAGE_LOCAL_TWIDDLE=1 \
  TWIDDLE_BRAM_STAGES=4 \
  USE_LOAD_PREPROCESS=$use_load_preprocess \
  FUSE_INTT_SCALE_IN_POST=$fuse_intt_scale_in_post \
  USE_FINAL_UNIT_TWIDDLE_BYPASS=$use_final_unit_twiddle_bypass \
  USE_TOP_DATA_BRAM=$use_top_data_bram \
  USE_SHARED_PERIPH_MONT=$use_shared_periph_mont \
  USE_NATURAL_AB_LOADER=$use_natural_ab_loader \
]

cd $repo_root
set run_start [clock seconds]
set_msg_config -id {Synth 8-7129} -limit 20
read_verilog -sv $rtl_files
synth_design -top poly_mul_top_dual_forward -part $part_name -generic $generic_args
create_clock -name clk -period $clock_period_ns [get_ports clk]

report_utilization -file [file join $report_dir utilization.rpt]
report_utilization -hierarchical -hierarchical_depth 10 \
  -file [file join $report_dir utilization_hierarchical.rpt]
catch {report_ram_utilization -file [file join $report_dir ram_utilization.rpt]}
report_timing_summary -file [file join $report_dir timing_summary.rpt]
report_timing -delay_type max -max_paths 10 -nworst 1 -sort_by group \
  -file [file join $report_dir timing_paths_top10.rpt]
report_power -file [file join $report_dir power.rpt]
write_checkpoint -force [file join $report_dir poly_mul_top_dual_forward_synth.dcp]

set fd [open [file join $report_dir config.txt] w]
puts $fd "vivado=[version -short]"
puts $fd "part=$part_name"
puts $fd "period_ns=$clock_period_ns"
puts $fd "top=poly_mul_top_dual_forward"
puts $fd "configuration=$config"
puts $fd "generics=$generic_args"
puts $fd "runtime_seconds=[expr {[clock seconds] - $run_start}]"
close $fd
puts "DSP-reduction synthesis complete: $report_dir"
exit 0
