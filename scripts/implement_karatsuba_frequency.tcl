# Internal-clock-only frequency experiment. No RTL or timing exceptions change.
if {$argc != 4} {error "Usage: <checkpoint> <output> <MHz> <incremental|fresh|targeted|reroute>"}
set checkpoint [file normalize [lindex $argv 0]]
set out [file normalize [lindex $argv 1]]
set mhz [lindex $argv 2]
set strategy [lindex $argv 3]
if {$mhz ni {160 170 180 185 190 200} || $strategy ni {incremental fresh targeted reroute}} {error "Invalid experiment"}
if {[version -short] ne "2026.1"} {error "Requires baseline Vivado 2026.1"}
set_param general.maxThreads 4
puts [help phys_opt_design]
file mkdir $out
set t0 [clock seconds]
open_checkpoint $checkpoint
if {[get_property PART [current_design]] ne "xc7vx485tffg1761-2"} {error "Part changed"}
if {[llength [get_cells -hier -filter {IS_BLACKBOX == 1}]]} {error "Black boxes"}
set period [expr {1000.0/$mhz}]
create_clock -name clk -period $period [get_ports clk]
set period [get_property PERIOD [get_clocks clk]]
write_xdc -force [file join $out constraints_before.xdc]
if {$strategy eq "fresh"} {
  opt_design -directive Explore
  write_checkpoint -force [file join $out optimized.dcp]
  place_design -directive AltSpreadLogic_medium
  write_checkpoint -force [file join $out placed.dcp]
  phys_opt_design -directive AggressiveFanoutOpt
  phys_opt_design -directive AggressiveExplore
  write_checkpoint -force [file join $out pre_route.dcp]
  route_design -directive MoreGlobalIterations -tns_cleanup
  write_checkpoint -force [file join $out routed_initial.dcp]
}
if {$strategy in {targeted reroute}} {
  # force_replication_on_nets is unsupported post-route in Vivado 2026.1.
  # The runner selects the original placed, physically optimized UNROUTED DCP.
  if {$strategy eq "targeted"} {
    source [file join [file dirname [info script]] karatsuba_targeted_fanout.tcl]
  }
  phys_opt_design -directive AggressiveExplore
  write_checkpoint -force [file join $out pre_route.dcp]
  route_design -directive MoreGlobalIterations -tns_cleanup
  write_checkpoint -force [file join $out routed_initial.dcp]
}
# Legal post-route directive, matching the baseline's final optimization step.
phys_opt_design -directive Explore
route_design -directive MoreGlobalIterations -tns_cleanup
update_timing
write_checkpoint -force [file join $out routed.dcp]
write_xdc -force [file join $out constraints_after.xdc]
report_utilization -file [file join $out utilization.rpt]
report_utilization -hierarchical -hierarchical_depth 4 -file [file join $out hierarchy.rpt]
report_timing_summary -delay_type min_max -check_timing_verbose -report_unconstrained -file [file join $out timing.rpt]
report_route_status -file [file join $out route_status.rpt]
report_drc -file [file join $out drc.rpt]
set regs [all_registers]
report_timing -from $regs -to $regs -delay_type max -max_paths 20 -file [file join $out internal_setup.rpt]
report_timing -from $regs -to $regs -delay_type min -max_paths 20 -file [file join $out internal_hold.rpt]
set p [get_timing_paths -from $regs -to $regs -delay_type max -max_paths 1]
set h [get_timing_paths -from $regs -to $regs -delay_type min -max_paths 1]
if {[llength $p] != 1 || [llength $h] != 1} {error "Missing register paths"}
set wns [get_property SLACK $p]
set whs [get_property SLACK $h]
set dsp [llength [get_cells -hier -filter {REF_NAME == DSP48E1}]]
set bram [llength [get_cells -hier -filter {REF_NAME == RAMB36E1}]]
if {$dsp != 246 || $bram != 59} {error "Unexpected DSP/BRAM ownership change: $dsp/$bram"}
set f [open [file join $out result.json] w]
puts $f "\{"
puts $f "  \"mhz\": $mhz, \"period_ns\": $period,"
puts $f "  \"wns_ns\": $wns, \"whs_ns\": $whs,"
puts $f "  \"internal_slack_pass\": [expr {$wns >= 0 && $whs >= 0 ? {true} : {false}}],"
puts $f "  \"dsp\": $dsp, \"bram36\": $bram,"
puts $f "  \"startpoint\": \"[get_property STARTPOINT_PIN $p]\","
puts $f "  \"endpoint\": \"[get_property ENDPOINT_PIN $p]\","
puts $f "  \"strategy\": \"$strategy\", \"runtime_seconds\": [expr {[clock seconds]-$t0}],"
puts $f "  \"board_signoff\": false"
puts $f "\}"
close $f
close_design
puts "FREQUENCY_IMPLEMENTATION_COMPLETE $mhz $strategy WNS=$wns WHS=$whs"
exit 0
