# Isolated full-top comparison. Uses the production implementation directives.
# External IO delays/pins are unspecified: report internal timing, not board signoff.
if {$argc != 4} {error "Usage: <synth|impl> <latency> <snapshot> <output>"}
set phase [lindex $argv 0]
set latency [lindex $argv 1]
set snapshot [file normalize [lindex $argv 2]]
set out [file normalize [lindex $argv 3]]
set part_name xc7vx485tffg1761-2
set target_period 6.667
set over_period 6.400
file mkdir $out
cd $snapshot
set_param general.maxThreads 4
set t0 [clock seconds]
if {$phase eq "synth"} {
  set f [open [file join $snapshot rtl_files.txt] r]
  set rtl_files [split [string trim [read $f]] "\n"]
  close $f
  set_msg_config -id {Synth 8-7129} -limit 20
  read_verilog -sv $rtl_files
  set generics [list MUL_LAT=$latency USE_WL_MONT=1 USE_WL_CORE=1 USE_WL_PRE_NTT=1 USE_WL_POINTWISE=1 USE_WL_POST_INTT=1 USE_BFU_BOUNDARY_PIPE=1 USE_STAGE_LOCAL_TWIDDLE=1 TWIDDLE_BRAM_STAGES=4 USE_LOAD_PREPROCESS=0 FUSE_INTT_SCALE_IN_POST=1 USE_FINAL_UNIT_TWIDDLE_BYPASS=1 USE_TOP_DATA_BRAM=1 USE_SHARED_PERIPH_MONT=1 USE_NATURAL_AB_LOADER=1]
  synth_design -top poly_mul_top_dual_forward -part $part_name -generic $generics
  create_clock -name clk -period $target_period [get_ports clk]
  report_utilization -file [file join $out utilization.rpt]
  report_utilization -hierarchical -hierarchical_depth 10 -file [file join $out hierarchy.rpt]
  report_ram_utilization -file [file join $out ram.rpt]
  report_timing_summary -delay_type min_max -check_timing_verbose -report_unconstrained -file [file join $out timing.rpt]
  write_checkpoint -force [file join $out synth.dcp]
} elseif {$phase eq "impl"} {
  open_checkpoint [file join $out .. synth synth.dcp]
  create_clock -name clk -period $over_period [get_ports clk]
  opt_design -directive Explore
  write_checkpoint -force [file join $out optimized_oc.dcp]
  place_design -directive AltSpreadLogic_medium
  write_checkpoint -force [file join $out placed_oc.dcp]
  report_timing_summary -file [file join $out timing_placed.rpt]
  phys_opt_design -directive AggressiveFanoutOpt
  phys_opt_design -directive AggressiveExplore
  write_checkpoint -force [file join $out pre_route_physopt_oc.dcp]
  route_design -directive MoreGlobalIterations -tns_cleanup
  write_checkpoint -force [file join $out routed_oc_initial.dcp]
  phys_opt_design -directive Explore
  route_design -directive MoreGlobalIterations -tns_cleanup
  write_checkpoint -force [file join $out routed_oc_final.dcp]
  create_clock -name clk -period $target_period [get_ports clk]
  update_timing
  write_checkpoint -force [file join $out routed_signoff.dcp]
  report_utilization -file [file join $out utilization.rpt]
  report_utilization -hierarchical -hierarchical_depth 10 -file [file join $out hierarchy.rpt]
  report_ram_utilization -file [file join $out ram.rpt]
  report_timing_summary -delay_type min_max -check_timing_verbose -report_unconstrained -file [file join $out timing.rpt]
  report_route_status -file [file join $out route_status.rpt]
  report_drc -file [file join $out drc.rpt]
  set regs [all_registers]
  report_timing -from $regs -to $regs -delay_type max -max_paths 10 -file [file join $out internal_setup.rpt]
  report_timing -from $regs -to $regs -delay_type min -max_paths 10 -file [file join $out internal_hold.rpt]
  set p [get_timing_paths -from $regs -to $regs -delay_type max -max_paths 1]
  set h [get_timing_paths -from $regs -to $regs -delay_type min -max_paths 1]
  if {[llength $p]!=1 || [llength $h]!=1} {error "Missing internal timing path"}
  set f [open [file join $out internal_timing.csv] w]
  puts $f "latency,wns_ns,whs_ns,data_path_delay_ns,startpoint,endpoint"
  puts $f "$latency,[get_property SLACK $p],[get_property SLACK $h],[get_property DATAPATH_DELAY $p],[get_property STARTPOINT_PIN $p],[get_property ENDPOINT_PIN $p]"
  close $f
} else {error "Unknown phase"}
set f [open [file join $out config.txt] w]
puts $f "vivado=[version -short]\npart=$part_name\nlatency=$latency\nreduction=fused2\nphase=$phase\nsnapshot=$snapshot\ntop=poly_mul_top_dual_forward\nconfiguration=natural_ab_raw_pre_shared\nperiod_ns=$target_period\nimplementation_period_ns=$over_period\nexternal_io_constraints=unspecified\nruntime_seconds=[expr {[clock seconds]-$t0}]"
close $f
puts "CSA_FULL_TOP_PHASE_PASS $phase L=$latency"
exit 0