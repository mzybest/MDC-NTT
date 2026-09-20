# Query register-to-register paths from saved routed OOC checkpoints.
# OOC port locations are unbound, so aggregate WNS can be reset-port dominated.
set root [file normalize [file join [file dirname [info script]] ..]]
cd $root
set out [file join $root reports wl_lowcost_modmul vivado]
set fd [open [file join $out internal_timing.csv] w]
puts $fd "impl,reg_to_reg_wns_ns,startpoint,endpoint"
foreach impl {0 1 2} {
  set dir [file join $out impl_$impl]
  open_checkpoint [file join $dir routed.dcp]
  set registers [all_registers]
  set path [get_timing_paths -from $registers -to $registers -delay_type max -max_paths 1]
  if {[llength $path] != 1} {error "No register-to-register timing path for impl=$impl"}
  set slack [get_property SLACK $path]
  set start [get_property STARTPOINT_PIN $path]
  set end [get_property ENDPOINT_PIN $path]
  report_timing -from $registers -to $registers -delay_type max -max_paths 10 -file [file join $dir internal_paths.rpt]
  puts $fd "$impl,$slack,$start,$end"
  flush $fd
  puts "WL_INTERNAL_TIMING impl=$impl WNS=$slack START=$start END=$end"
  close_design
}
close $fd
puts "WL_INTERNAL_TIMING_PASS"
