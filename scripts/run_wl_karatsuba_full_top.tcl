# Candidate-only full-top run; directives/clock periods match fused14 reference.
# The source snapshot changes only BFU selector sites. All four peripheral
# Montgomery multipliers retain their original complete 64-bit integer core.
# IO delays/pins are unspecified, as in the reference: no board/Fmax signoff.
if {$argc != 3} {error "Usage: <synth|impl> <snapshot> <output>"}
set phase [lindex $argv 0]
if {$phase ni {synth impl}} {error "Unknown phase: $phase"}
set snapshot [file normalize [lindex $argv 1]]
set out [file normalize [lindex $argv 2]]
set latency 14
set part_name xc7vx485tffg1761-2
set target_period 6.667
set over_period 6.400
if {[version -short] ne "2026.1"} {error "This comparison requires Vivado 2026.1"}
file mkdir $out
cd $snapshot
set_param general.maxThreads 4
set t0 [clock seconds]

proc audit_frontends {out phase} {
  # Default synth hierarchy is rebuilt, matching the existing production flow.
  # Inspect actual instantiated integer frontends, not an assumed DSP budget.
  set core_count 0
  set pool_count 0
  set cells [get_cells -hier -filter {NAME =~ */u_intmul}]
  set f [open [file join $out isolation_audit.txt] w]
  puts $f "phase=$phase"
  foreach cell $cells {
    set name [get_property NAME $cell]
    set ref [get_property REF_NAME $cell]
    puts $f "$name REF_NAME=$ref"
    if {[string match {u_core_a/*} $name] || [string match {u_core_b/*} $name]} {
      if {![string match {intmul_60x60_karatsuba4_experimental*} $ref]} {
        close $f
        error "Unexpected core integer frontend: $name $ref"
      }
      incr core_count
    } elseif {[string match {g_shared_periph_pool.u_pool/*} $name]} {
      if {![string match {intmul_64x64_24x17*} $ref]} {
        close $f
        error "Peripheral integer frontend is not the original full64 module: $name $ref"
      }
      incr pool_count
    } else {
      close $f
      error "Unexpected integer frontend outside the 22-core / 4-pool boundary: $name"
    }
  }
  puts $f "core_karatsuba_frontends=$core_count"
  puts $f "peripheral_full64_frontends=$pool_count"
  set blackboxes [get_cells -hier -filter {IS_BLACKBOX == 1}]
  puts $f "black_boxes=[llength $blackboxes]"
  set dsp_cells [get_cells -hier -filter {REF_NAME == DSP48E1}]
  puts $f "dsp_total=[llength $dsp_cells]"
  set core_a_dsp 0
  set core_b_dsp 0
  set pool_dsp 0
  set other_dsp 0
  foreach cell $dsp_cells {
    set name [get_property NAME $cell]
    if {[string match {u_core_a/*} $name]} {incr core_a_dsp
    } elseif {[string match {u_core_b/*} $name]} {incr core_b_dsp
    } elseif {[string match {g_shared_periph_pool.u_pool/*} $name]} {incr pool_dsp
    } else {incr other_dsp}
  }
  puts $f "core_a_dsp=$core_a_dsp\ncore_b_dsp=$core_b_dsp\nperipheral_dsp=$pool_dsp\nother_dsp=$other_dsp"
  close $f
  if {$core_count != 22 || $pool_count != 4 || [llength $blackboxes] != 0} {
    error "Frontend/black-box audit failed: core=$core_count peripheral=$pool_count black_boxes=[llength $blackboxes]"
  }
}

if {$phase eq "synth"} {
  set f [open [file join $snapshot rtl_files.txt] r]
  set rtl_files [split [string trim [read $f]] "\n"]
  close $f
  set_msg_config -id {Synth 8-7129} -limit 20
  read_verilog -sv $rtl_files
  set generics [list MUL_LAT=14 USE_WL_MONT=1 USE_WL_CORE=1 USE_WL_PRE_NTT=1 USE_WL_POINTWISE=1 USE_WL_POST_INTT=1 USE_BFU_BOUNDARY_PIPE=1 USE_STAGE_LOCAL_TWIDDLE=1 TWIDDLE_BRAM_STAGES=4 USE_LOAD_PREPROCESS=0 FUSE_INTT_SCALE_IN_POST=1 USE_FINAL_UNIT_TWIDDLE_BYPASS=1 USE_TOP_DATA_BRAM=1 USE_SHARED_PERIPH_MONT=1 USE_NATURAL_AB_LOADER=1]
  synth_design -top poly_mul_top_dual_forward -part $part_name -generic $generics
  create_clock -name clk -period $target_period [get_ports clk]
  audit_frontends $out $phase
  report_utilization -file [file join $out utilization.rpt]
  report_utilization -hierarchical -hierarchical_depth 10 -file [file join $out hierarchy.rpt]
  report_ram_utilization -file [file join $out ram.rpt]
  report_timing_summary -delay_type min_max -check_timing_verbose -report_unconstrained -file [file join $out timing.rpt]
  write_checkpoint -force [file join $out synth.dcp]
} else {
  open_checkpoint [file join $out .. synth synth.dcp]
  audit_frontends $out $phase
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
  audit_frontends $out $phase
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
  if {[llength $p] != 1 || [llength $h] != 1} {error "Missing internal timing path"}
  set f [open [file join $out internal_timing.csv] w]
  puts $f "latency,wns_ns,whs_ns,data_path_delay_ns,startpoint,endpoint"
  puts $f "$latency,[get_property SLACK $p],[get_property SLACK $h],[get_property DATAPATH_DELAY $p],[get_property STARTPOINT_PIN $p],[get_property ENDPOINT_PIN $p]"
  close $f
}
set f [open [file join $out config.txt] w]
puts $f "vivado=[version -short]\npart=$part_name\nlatency=$latency\nreduction=fused2\nphase=$phase\nsnapshot=$snapshot\ntop=poly_mul_top_dual_forward\nconfiguration=natural_ab_raw_pre_shared\nvariant=core22_karatsuba14_peripheral4_full64\nperiod_ns=$target_period\nimplementation_period_ns=$over_period\nexternal_io_constraints=unspecified\nruntime_seconds=[expr {[clock seconds]-$t0}]"
close $f
puts "KARATSUBA_FULL_TOP_PHASE_PASS $phase L=$latency"
exit 0
