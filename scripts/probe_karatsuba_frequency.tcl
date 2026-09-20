# Read-only timing/critical-control investigation of the accepted routed design.
if {$argc ni {2 3}} {error "Usage: <routed_checkpoint> <output_directory> [MHz list]"}
set checkpoint [file normalize [lindex $argv 0]]
set out [file normalize [lindex $argv 1]]
file mkdir $out
set_param general.maxThreads 4
open_checkpoint $checkpoint
if {[get_property PART [current_design]] ne "xc7vx485tffg1761-2"} {error "Unexpected part"}
if {[llength [get_cells -hier -filter {IS_BLACKBOX == 1}]] != 0} {error "Black boxes"}
help phys_opt_design
help report_high_fanout_nets
set f [open [file join $out baseline_recheck.csv] w]
puts $f "mhz,period_ns,wns_ns,whs_ns,startpoint,endpoint"
set regs [all_registers]
set frequencies {150 160 170 180}
if {$argc == 3} {set frequencies [lindex $argv 2]}
foreach mhz $frequencies {
  set period [expr {1000.0/$mhz}]
  create_clock -name clk -period $period [get_ports clk]
  set period [get_property PERIOD [get_clocks clk]]
  update_timing
  set p [get_timing_paths -from $regs -to $regs -delay_type max -max_paths 1]
  set h [get_timing_paths -from $regs -to $regs -delay_type min -max_paths 1]
  if {[llength $p] != 1 || [llength $h] != 1} {error "Missing register paths"}
  puts $f "$mhz,$period,[get_property SLACK $p],[get_property SLACK $h],[get_property STARTPOINT_PIN $p],[get_property ENDPOINT_PIN $p]"
  flush $f
  report_timing_summary -delay_type min_max -check_timing_verbose -report_unconstrained -file [file join $out timing_${mhz}.rpt]
  report_timing -from $regs -to $regs -delay_type max -max_paths 50 -file [file join $out internal_setup_${mhz}.rpt]
  report_timing -from $regs -to $regs -delay_type min -max_paths 20 -file [file join $out internal_hold_${mhz}.rpt]
}
close $f
set control [get_cells -hier -filter {NAME == u_core_a/g_stage_r_11}]
if {[llength $control] != 1} {error "Missing original critical driver"}
set f [open [file join $out critical_control.txt] w]
puts $f "CELL=$control"
foreach prop [list_property $control] {puts $f "$prop=[get_property $prop $control]"}
foreach pin [get_pins -of_objects $control] {
  puts $f "PIN=$pin DIRECTION=[get_property DIRECTION $pin] NET=[get_nets -of_objects $pin]"
  if {[get_property DIRECTION $pin] eq "IN" && [get_property REF_PIN_NAME $pin] ne "C"} {
    puts $f "FANIN_STARTS=[all_fanin -flat -startpoints_only -to $pin]"
  }
}
set q [get_pins -of_objects $control -filter {REF_PIN_NAME == Q}]
set net [get_nets -of_objects $q]
puts $f "Q_NET=$net"
puts $f "LOADS=[get_pins -of_objects [get_nets -segments $net] -filter {DIRECTION == IN}]"
close $f
set last_mhz [lindex $frequencies end]
report_timing -from $regs -to $regs -delay_type max -max_paths 20 -file [file join $out critical_setup_${last_mhz}.rpt]
report_route_status -file [file join $out route_status.rpt]
write_xdc -force [file join $out constraints_${last_mhz}.xdc]
puts "FREQUENCY_PROBE_PASS"
exit 0
