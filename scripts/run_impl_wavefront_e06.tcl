# Post-route implementation for the mode-tagged dual-context wavefront top.
set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ..]]
set synth_dir [file join $repo_root reports dual_context_wavefront synth]
set report_dir [file join $repo_root reports dual_context_wavefront impl_e06]
file mkdir $report_dir

set synth_dcp [file join $synth_dir poly_mul_top_wavefront_synth.dcp]
if {![file exists $synth_dcp]} {
  error "Missing synthesis checkpoint: $synth_dcp"
}

set run_start [clock seconds]
open_checkpoint $synth_dcp
opt_design -directive Explore
write_checkpoint -force [file join $report_dir optimized.dcp]
place_design -directive AltSpreadLogic_medium
write_checkpoint -force [file join $report_dir placed.dcp]
phys_opt_design -directive AggressiveFanoutOpt
write_checkpoint -force [file join $report_dir pre_route_physopt.dcp]
route_design -directive MoreGlobalIterations
write_checkpoint -force [file join $report_dir routed.dcp]

report_timing_summary -file [file join $report_dir timing_summary.rpt]
report_timing -delay_type max -max_paths 10 -nworst 10 -sort_by group \
  -file [file join $report_dir timing_paths_top10.rpt]
report_utilization -file [file join $report_dir utilization.rpt]
report_utilization -hierarchical -hierarchical_depth 7 \
  -file [file join $report_dir utilization_hierarchical.rpt]
catch {report_ram_utilization -file [file join $report_dir ram_utilization.rpt]}
report_power -file [file join $report_dir power.rpt]
report_route_status -file [file join $report_dir route_status.rpt]

set fd [open [file join $report_dir flow.txt] w]
puts $fd "vivado=[version -short]"
puts $fd "top=poly_mul_top_wavefront"
puts $fd "period_ns=10.0"
puts $fd "opt=Explore"
puts $fd "place=AltSpreadLogic_medium"
puts $fd "pre_phys=AggressiveFanoutOpt"
puts $fd "route=MoreGlobalIterations"
puts $fd "runtime_seconds=[expr {[clock seconds] - $run_start}]"
close $fd
puts "Dual-context wavefront e06 implementation complete: $report_dir"
exit 0
