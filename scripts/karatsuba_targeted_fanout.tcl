# Called after opening the original placed, unrouted checkpoint and setting target clock.
# This duplicates an existing register; it does not insert a pipeline stage.
set driver [get_cells -hier -filter {NAME == u_core_a/g_stage_r_11}]
if {[llength $driver] != 1} {error "Expected audited critical driver"}
set qpin [get_pins -of_objects $driver -filter {REF_PIN_NAME == Q}]
set target_net [get_nets -of_objects $qpin]
if {[llength $target_net] != 1} {error "Missing critical driver net"}
set f [open [file join $out targeted_fanout.txt] w]
puts $f "target_driver=$driver\ntarget_net=$target_net"
puts $f "before_load_pins=[llength [get_pins -leaf -of_objects [get_nets -segments $target_net] -filter {DIRECTION == IN}]]"
# Trace the complete same-clock register chain, rather than trusting inherited
# FILE_NAME attributes after synthesis has merged structurally equivalent logic.
set trace_cell $driver
for {set n 0} {$n < 20} {incr n} {
  puts $f "trace_cell=$trace_cell"
  foreach pin [get_pins -of_objects $trace_cell -filter {DIRECTION == IN}] {
    if {[get_property REF_PIN_NAME $pin] ne "C"} {
      puts $f "  $pin net=[get_nets -of_objects $pin] starts=[all_fanin -quiet -flat -startpoints_only -to $pin]"
    }
  }
  set d [get_pins -of_objects $trace_cell -filter {REF_PIN_NAME == D}]
  set starts [all_fanin -quiet -flat -startpoints_only -to $d]
  if {[llength $starts] != 1} {break}
  set previous [get_cells -quiet -of_objects $starts]
  if {[llength $previous] != 1 || [get_property REF_NAME $previous] ne "FDRE"} {break}
  set trace_cell $previous
}
flush $f
phys_opt_design -force_replication_on_nets $target_net
foreach cell [get_cells -hier -filter {NAME =~ u_core_a/g_stage_r_11*}] {
  set q [get_pins -quiet -of_objects $cell -filter {REF_PIN_NAME == Q}]
  if {[llength $q]} {
    set nets [get_nets -segments -of_objects $q]
    puts $f "after_cell=$cell loads=[llength [get_pins -leaf -of_objects $nets -filter {DIRECTION == IN}]]"
  }
}
close $f
write_checkpoint -force [file join $out targeted_replication.dcp]
