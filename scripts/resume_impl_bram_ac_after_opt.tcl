# Resume the BRAM A/C overconstrained flow from an opt_design checkpoint.
set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ..]]

if {$argc < 4} {
  error "Usage: <optimized_checkpoint_subpath> <report_subdir> <target_period_ns> <over_period_ns>"
}

set checkpoint_subpath [lindex $argv 0]
set report_subdir [lindex $argv 1]
set target_period [lindex $argv 2]
set over_period [lindex $argv 3]
set optimized_dcp [file join $repo_root reports dual_forward_dsp_reduction $checkpoint_subpath]
set report_dir [file join $repo_root reports dual_forward_dsp_reduction $report_subdir]
file mkdir $report_dir

if {![file exists $optimized_dcp]} {
  error "Missing optimized checkpoint: $optimized_dcp"
}

set run_start [clock seconds]
open_checkpoint $optimized_dcp
create_clock -name clk -period $over_period [get_ports clk]

place_design -directive AltSpreadLogic_medium
write_checkpoint -force [file join $report_dir placed_oc.dcp]
report_timing_summary -file [file join $report_dir timing_placed_oc.rpt]

phys_opt_design -directive AggressiveFanoutOpt
phys_opt_design -directive AggressiveExplore
write_checkpoint -force [file join $report_dir pre_route_physopt_oc.dcp]
report_timing_summary -file [file join $report_dir timing_pre_route_physopt_oc.rpt]

route_design -directive MoreGlobalIterations -tns_cleanup
write_checkpoint -force [file join $report_dir routed_oc_initial.dcp]
report_timing_summary -file [file join $report_dir timing_routed_oc_initial.rpt]

phys_opt_design -directive Explore
route_design -directive MoreGlobalIterations -tns_cleanup
write_checkpoint -force [file join $report_dir routed_oc_final.dcp]
report_timing_summary -file [file join $report_dir timing_routed_oc_final.rpt]

create_clock -name clk -period $target_period [get_ports clk]
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

set fd [open [file join $report_dir flow_resume.txt] w]
puts $fd "vivado=[version -short]"
puts $fd "top=poly_mul_top_dual_forward"
puts $fd "source_checkpoint=$optimized_dcp"
puts $fd "implementation_period_ns=$over_period"
puts $fd "signoff_period_ns=$target_period"
puts $fd "resume_stage=place_design"
puts $fd "place=AltSpreadLogic_medium"
puts $fd "pre_phys_1=AggressiveFanoutOpt"
puts $fd "pre_phys_2=AggressiveExplore"
puts $fd "route=MoreGlobalIterations"
puts $fd "route_tns_cleanup=1"
puts $fd "post_route_phys=Explore"
puts $fd "runtime_seconds=[expr {[clock seconds] - $run_start}]"
close $fd

puts "Resumed overconstrained implementation complete: $report_dir"
exit 0
