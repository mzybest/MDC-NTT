# Force post-route physical optimization on the known-good e06 route by using
# a 9.8 ns implementation target, then restore 10.0 ns for final signoff.
# No RTL or timing exceptions are changed.
set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ..]]
set base_dir [file join $repo_root reports dual_forward_bfu_selective_pipe]
set routed_dcp [file join $base_dir impl_e06 routed.dcp]
set report_dir [file join $base_dir postroute_physopt_explore_oc9p8]
file mkdir $report_dir
if {![file exists $routed_dcp]} { error "Missing checkpoint: $routed_dcp" }

set run_start [clock seconds]
open_checkpoint $routed_dcp
create_clock -name clk -period 9.8 [get_ports clk]

report_timing_summary -file [file join $report_dir timing_summary_before_9p8.rpt]
phys_opt_design -directive Explore
write_checkpoint -force [file join $report_dir postroute_physopt_9p8.dcp]

route_design -directive MoreGlobalIterations -tns_cleanup
write_checkpoint -force [file join $report_dir routed_9p8.dcp]
report_timing_summary -file [file join $report_dir timing_summary_9p8.rpt]

create_clock -name clk -period 10.0 [get_ports clk]
update_timing
write_checkpoint -force [file join $report_dir routed_signoff_10ns.dcp]
report_timing_summary -file [file join $report_dir timing_summary_signoff_10ns.rpt]
report_timing -delay_type max -max_paths 10 -nworst 1 -sort_by group \
  -file [file join $report_dir timing_paths_signoff_10ns_top10.rpt]
report_utilization -file [file join $report_dir utilization_signoff_10ns.rpt]
report_power -file [file join $report_dir power_signoff_10ns.rpt]
report_route_status -file [file join $report_dir route_status_signoff_10ns.rpt]

set fd [open [file join $report_dir flow.txt] w]
puts $fd "vivado=[version -short]"
puts $fd "source_checkpoint=$routed_dcp"
puts $fd "implementation_period_ns=9.8"
puts $fd "signoff_period_ns=10.0"
puts $fd "post_route_phys=Explore"
puts $fd "reroute=MoreGlobalIterations"
puts $fd "tns_cleanup=1"
puts $fd "runtime_seconds=[expr {[clock seconds] - $run_start}]"
close $fd
exit 0
