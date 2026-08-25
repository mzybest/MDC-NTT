# XC7VX485T 150 MHz implementation flow for Proteus-oriented comparisons.
#
# Usage:
#   vivado -mode batch -source <this-script> -tclargs \
#     <full|ntt_only|dualctx> <part> <signoff_period_ns> \
#     <implementation_period_ns> <report_subdir>

set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ..]]

if {$argc < 5} {
  error "Usage: <full|ntt_only|dualctx> <part> <signoff_period_ns> <implementation_period_ns> <report_subdir>"
}

set variant [lindex $argv 0]
set part_name [lindex $argv 1]
set signoff_period [lindex $argv 2]
set implementation_period [lindex $argv 3]
set report_subdir [lindex $argv 4]
set report_dir [file join $repo_root reports proteus_xc7vx485t_150mhz $report_subdir]
file mkdir $report_dir

set common_rtl [list \
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
  rtl/twiddle_rom_stage_ntt.sv \
]

switch -- $variant {
  full {
    set top_name poly_mul_top_dual_forward
    set rtl_files [concat $common_rtl [list \
      rtl/psi_rom.sv \
      rtl/psi_post_rom.sv \
      rtl/mdc_stage.sv \
      rtl/gs_mdc_core.sv \
      rtl/gs_mdc_core_ntt_only.sv \
      rtl/pointwise_mul.sv \
      rtl/top_data_bram.sv \
      rtl/poly_mul_top_dual_forward.sv \
    ]]
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
      USE_LOAD_PREPROCESS=0 \
      FUSE_INTT_SCALE_IN_POST=1 \
      USE_FINAL_UNIT_TWIDDLE_BYPASS=1 \
      USE_TOP_DATA_BRAM=1 \
    ]
  }
  ntt_only {
    set top_name gs_mdc_core_ntt_only
    set rtl_files [concat $common_rtl [list \
      rtl/mdc_stage.sv \
      rtl/gs_mdc_core_ntt_only.sv \
    ]]
    set generic_args [list \
      MUL_LAT=14 \
      USE_WL_MONT=1 \
      BYPASS_FINAL_UNIT_TWIDDLE=1 \
      BFU_BOUNDARY_PIPE_MASK=1 \
      TWIDDLE_BRAM_STAGES=4 \
    ]
  }
  dualctx {
    set top_name gs_mdc_core_dualctx
    set rtl_files [concat $common_rtl [list \
      rtl/mdc_reorder_context.sv \
      rtl/mdc_stage_dualctx.sv \
      rtl/gs_mdc_core_dualctx.sv \
    ]]
    set generic_args [list \
      MUL_LAT=14 \
      USE_WL_MONT=1 \
      USE_STAGE_LOCAL_TWIDDLE=1 \
      TWIDDLE_BRAM_STAGES=4 \
      FRAME_W=2 \
    ]
  }
  default {
    error "Unknown variant: $variant"
  }
}

cd $repo_root
set run_start [clock seconds]
set_msg_config -id {Synth 8-7129} -limit 20
read_verilog -sv $rtl_files
synth_design -top $top_name -part $part_name -generic $generic_args
create_clock -name clk -period $implementation_period [get_ports clk]

report_utilization -file [file join $report_dir utilization_synth.rpt]
report_timing_summary -file [file join $report_dir timing_synth.rpt]
write_checkpoint -force [file join $report_dir synthesized.dcp]

opt_design -directive Explore
write_checkpoint -force [file join $report_dir optimized.dcp]

place_design -directive AltSpreadLogic_medium
write_checkpoint -force [file join $report_dir placed.dcp]
report_timing_summary -file [file join $report_dir timing_placed.rpt]

phys_opt_design -directive AggressiveFanoutOpt
phys_opt_design -directive AggressiveExplore
write_checkpoint -force [file join $report_dir pre_route_physopt.dcp]
report_timing_summary -file [file join $report_dir timing_pre_route_physopt.rpt]

route_design -directive MoreGlobalIterations -tns_cleanup
write_checkpoint -force [file join $report_dir routed_initial.dcp]
report_timing_summary -file [file join $report_dir timing_routed_initial.rpt]

phys_opt_design -directive Explore
route_design -directive MoreGlobalIterations -tns_cleanup
write_checkpoint -force [file join $report_dir routed_final.dcp]

# Restore the requested 150 MHz clock for the official signoff reports.
create_clock -name clk -period $signoff_period [get_ports clk]
update_timing
write_checkpoint -force [file join $report_dir routed_signoff.dcp]

report_timing_summary -file [file join $report_dir timing_signoff.rpt]
report_timing -delay_type max -max_paths 10 -nworst 1 -sort_by group \
  -file [file join $report_dir timing_paths_signoff_top10.rpt]
report_utilization -file [file join $report_dir utilization_signoff.rpt]
report_utilization -hierarchical -hierarchical_depth 10 \
  -file [file join $report_dir utilization_hierarchical_signoff.rpt]
catch {report_ram_utilization -file [file join $report_dir ram_utilization_signoff.rpt]}
report_power -file [file join $report_dir power_signoff.rpt]
report_route_status -file [file join $report_dir route_status_signoff.rpt]

set fd [open [file join $report_dir config.txt] w]
puts $fd "vivado=[version -short]"
puts $fd "variant=$variant"
puts $fd "top=$top_name"
puts $fd "part=$part_name"
puts $fd "implementation_period_ns=$implementation_period"
puts $fd "signoff_period_ns=$signoff_period"
puts $fd "generics=$generic_args"
puts $fd "opt=Explore"
puts $fd "place=AltSpreadLogic_medium"
puts $fd "pre_phys_1=AggressiveFanoutOpt"
puts $fd "pre_phys_2=AggressiveExplore"
puts $fd "route=MoreGlobalIterations"
puts $fd "post_route_phys=Explore"
puts $fd "runtime_seconds=[expr {[clock seconds] - $run_start}]"
close $fd

puts "XC7VX485T 150 MHz comparison implementation complete: $variant"
exit 0
