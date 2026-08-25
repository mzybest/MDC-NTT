# Overconstrained implementation flow for the BRAM A/C scratch dual-forward top.
# The implementation clock is tightened during opt/place/route, then restored
# to the requested target period for final signoff.
set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ..]]

if {$argc < 4} {
  error "Usage: <synth_subdir> <report_subdir> <target_period_ns> <over_period_ns>"
}

set synth_subdir [lindex $argv 0]
set report_subdir [lindex $argv 1]
set target_period [lindex $argv 2]
set over_period [lindex $argv 3]
set synth_dir [file join $repo_root reports dual_forward_dsp_reduction $synth_subdir]
set report_dir [file join $repo_root reports dual_forward_dsp_reduction $report_subdir]
set synth_dcp [file join $synth_dir poly_mul_top_dual_forward_synth.dcp]
file mkdir $report_dir

if {![file exists $synth_dcp]} {
  error "Missing synthesis checkpoint: $synth_dcp"
}

set run_start [clock seconds]
open_checkpoint $synth_dcp
create_clock -name clk -period $over_period [get_ports clk]

opt_design -directive Explore
write_checkpoint -force [file join $report_dir optimized_oc.dcp]

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

# Restore the requested user clock for the only timing result used as signoff.
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

set fd [open [file join $report_dir flow.txt] w]
puts $fd "vivado=[version -short]"
puts $fd "top=poly_mul_top_dual_forward"
puts $fd "source_checkpoint=$synth_dcp"
puts $fd "implementation_period_ns=$over_period"
puts $fd "signoff_period_ns=$target_period"
puts $fd "opt=Explore"
puts $fd "place=AltSpreadLogic_medium"
puts $fd "pre_phys_1=AggressiveFanoutOpt"
puts $fd "pre_phys_2=AggressiveExplore"
puts $fd "route=MoreGlobalIterations"
puts $fd "route_tns_cleanup=1"
puts $fd "post_route_phys=Explore"
puts $fd "runtime_seconds=[expr {[clock seconds] - $run_start}]"
close $fd

puts "Overconstrained BRAM A/C implementation complete: $report_dir"
exit 0
