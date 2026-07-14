# Vivado 2022.2 non-project implementation directive sweep for poly_mul_top.
#
# Usage:
#   vivado -mode batch -source scripts/run_impl_directive_sweep.tcl \
#     -tclargs xc7a200tsbg484-1 10.0 <experiment_name>
#
# Each experiment intentionally runs synth_design through route_design from a
# fresh Vivado process. The batch wrapper invokes this script once per entry.

set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ..]]
set sweep_root [file join $repo_root reports directive_sweep]
file mkdir $sweep_root

set part_name "xc7a200tsbg484-1"
set clock_period_ns 10.0
set experiment_name "e00_baseline"
if {$argc >= 1} { set part_name [lindex $argv 0] }
if {$argc >= 2} { set clock_period_ns [lindex $argv 1] }
if {$argc >= 3} { set experiment_name [lindex $argv 2] }

# All directives below were taken from Vivado 2022.2 command help. "None"
# means that the optional post-route physical optimization pass is omitted.
set experiments [dict create \
  e00_baseline [dict create \
    opt Default place Default pre_phys Default route Default route_tns 0 post_phys None] \
  e01_all_explore [dict create \
    opt Explore place Explore pre_phys Explore route Explore route_tns 0 post_phys None] \
  e02_extra_timing_aggressive [dict create \
    opt Explore place ExtraTimingOpt pre_phys AggressiveExplore route AggressiveExplore route_tns 0 post_phys None] \
  e03_early_block_explore [dict create \
    opt Default place EarlyBlockPlacement pre_phys Explore route Explore route_tns 0 post_phys None] \
  e04_wirelength_higher_delay [dict create \
    opt Default place WLDrivenBlockPlacement pre_phys Explore route HigherDelayCost route_tns 0 post_phys None] \
  e05_spread_low_explore [dict create \
    opt Explore place AltSpreadLogic_low pre_phys Explore route Explore route_tns 0 post_phys None] \
  e06_spread_medium_fanout [dict create \
    opt Explore place AltSpreadLogic_medium pre_phys AggressiveFanoutOpt route MoreGlobalIterations route_tns 0 post_phys None] \
  e07_netdelay_no_relax [dict create \
    opt Explore place ExtraNetDelay_high pre_phys Explore route NoTimingRelaxation route_tns 0 post_phys None] \
  e08_postroute_explore [dict create \
    opt Explore place ExtraTimingOpt pre_phys Explore route Explore route_tns 1 post_phys Explore] \
  e09_remap_aggressive_post [dict create \
    opt ExploreWithRemap place Explore pre_phys AggressiveExplore route AggressiveExplore route_tns 1 post_phys Explore] \
  e10_timing_fanout_post [dict create \
    opt Explore place ExtraTimingOpt pre_phys AggressiveFanoutOpt route MoreGlobalIterations route_tns 1 post_phys Explore] \
  e11_wirelength_post [dict create \
    opt ExploreWithRemap place WLDrivenBlockPlacement pre_phys Explore route HigherDelayCost route_tns 1 post_phys Explore] \
]

if {$experiment_name eq "list"} {
  foreach name [dict keys $experiments] {
    set cfg [dict get $experiments $name]
    puts [format "%s opt=%s place=%s pre_phys=%s route=%s tns=%s post_phys=%s" \
      $name [dict get $cfg opt] [dict get $cfg place] \
      [dict get $cfg pre_phys] [dict get $cfg route] \
      [dict get $cfg route_tns] [dict get $cfg post_phys]]
  }
  exit 0
}

if {![dict exists $experiments $experiment_name]} {
  error "Unknown experiment '$experiment_name'. Use experiment name 'list' to show valid entries."
}

proc write_text {path data} {
  set fd [open $path w]
  puts -nonewline $fd $data
  close $fd
}

proc read_text {path} {
  set fd [open $path r]
  set data [read $fd]
  close $fd
  return $data
}

proc csv_quote {value} {
  set escaped [string map [list "\"" "\"\""] $value]
  return "\"${escaped}\""
}

proc format_duration {seconds} {
  set hours [expr {$seconds / 3600}]
  set minutes [expr {($seconds % 3600) / 60}]
  set secs [expr {$seconds % 60}]
  return [format "%02d:%02d:%02d" $hours $minutes $secs]
}

proc run_directive_command {command directive} {
  if {$directive eq "Default"} {
    uplevel 1 [list $command]
  } else {
    uplevel 1 [list $command -directive $directive]
  }
}

proc run_route_command {directive use_tns_cleanup} {
  set args [list route_design]
  if {$directive ne "Default"} {
    lappend args -directive $directive
  }
  if {$use_tns_cleanup} {
    lappend args -tns_cleanup
  }
  uplevel 1 $args
}

proc parse_timing_summary {text} {
  set found_header 0
  foreach line [split $text "\n"] {
    if {!$found_header && [string first "WNS(ns)" $line] >= 0} {
      set found_header 1
      continue
    }
    if {$found_header && [regexp {^\s*(-?[0-9]+\.[0-9]+)\s+(-?[0-9]+\.[0-9]+)\s+[0-9]+\s+[0-9]+\s+(-?[0-9]+\.[0-9]+)\s+(-?[0-9]+\.[0-9]+)} $line -> wns tns whs ths]} {
      return [list $wns $tns $whs $ths]
    }
  }
  return [list NA NA NA NA]
}

proc parse_utilization {text} {
  set lut NA
  set lut_mem NA
  set ff NA
  set dsp NA
  set bram NA
  regexp {\|\s*Slice LUTs\s*\|\s*([0-9]+)\s*\|} $text -> lut
  regexp {\|\s*LUT as Memory\s*\|\s*([0-9]+)\s*\|} $text -> lut_mem
  regexp {\|\s*Slice Registers\s*\|\s*([0-9]+)\s*\|} $text -> ff
  regexp {\|\s*DSPs\s*\|\s*([0-9]+)\s*\|} $text -> dsp
  regexp {\|\s*Block RAM Tile\s*\|\s*([0-9]+)\s*\|} $text -> bram
  return [list $lut $lut_mem $ff $dsp $bram]
}

proc parse_power {text} {
  set power NA
  regexp {\|\s*Total On-Chip Power \(W\)\s*\|\s*([0-9]+\.[0-9]+)} $text -> power
  return $power
}

set cfg [dict get $experiments $experiment_name]
set opt_directive [dict get $cfg opt]
set place_directive [dict get $cfg place]
set pre_phys_directive [dict get $cfg pre_phys]
set route_directive [dict get $cfg route]
set route_tns_cleanup [dict get $cfg route_tns]
set post_phys_directive [dict get $cfg post_phys]

set experiment_dir [file join $sweep_root $experiment_name]
file mkdir $experiment_dir
set completion_file [file join $experiment_dir COMPLETE.txt]
if {[file exists $completion_file]} {
  puts "Experiment $experiment_name is already complete; preserving existing results."
  exit 0
}

set rtl_files [list \
  rtl/params_pkg.sv \
  rtl/mod_add.sv \
  rtl/mod_sub.sv \
  rtl/delay_line.sv \
  rtl/delay_memory.sv \
  rtl/mont_mul.sv \
  rtl/intmul_64x64_24x17.sv \
  rtl/wlmont_round16.sv \
  rtl/mont_mul_wl.sv \
  rtl/mont_mul_select.sv \
  rtl/gs_butterfly.sv \
  rtl/twiddle_rom.sv \
  rtl/psi_rom.sv \
  rtl/mdc_stage.sv \
  rtl/gs_mdc_core.sv \
  rtl/dual_port_ram.sv \
  rtl/pointwise_mul.sv \
  rtl/poly_mul_top.sv \
]

set generic_args [list \
  MUL_LAT=14 \
  USE_WL_MONT=1 \
  USE_WL_CORE=1 \
  USE_WL_PRE_NTT=1 \
  USE_WL_POINTWISE=1 \
  USE_WL_POST_INTT=1 \
]

set config_text "experiment=$experiment_name\n"
append config_text "vivado=[version -short]\n"
append config_text "part=$part_name\nperiod_ns=$clock_period_ns\n"
append config_text "generics=$generic_args\n"
append config_text "opt=$opt_directive\nplace=$place_directive\n"
append config_text "pre_phys=$pre_phys_directive\nroute=$route_directive\n"
append config_text "route_tns_cleanup=$route_tns_cleanup\npost_phys=$post_phys_directive\n"
write_text [file join $experiment_dir experiment_config.txt] $config_text

set_msg_config -id {Synth 8-7129} -limit 20
set run_start [clock seconds]

if {[catch {
  cd $repo_root
  read_verilog -sv $rtl_files
  synth_design -top poly_mul_top -part $part_name -generic $generic_args
  create_clock -name clk -period $clock_period_ns [get_ports clk]
  write_checkpoint -force [file join $experiment_dir synthesized.dcp]

  run_directive_command opt_design $opt_directive
  write_checkpoint -force [file join $experiment_dir optimized.dcp]

  run_directive_command place_design $place_directive
  write_checkpoint -force [file join $experiment_dir placed.dcp]

  run_directive_command phys_opt_design $pre_phys_directive
  write_checkpoint -force [file join $experiment_dir pre_route_physopt.dcp]

  run_route_command $route_directive $route_tns_cleanup

  if {$post_phys_directive ne "None"} {
    write_checkpoint -force [file join $experiment_dir routed_before_post_physopt.dcp]
    run_directive_command phys_opt_design $post_phys_directive
    write_checkpoint -force [file join $experiment_dir post_route_physopt.dcp]
    # Physical optimization can invalidate individual routes. Re-run the same
    # legal timing-oriented router directive to produce the signoff design.
    run_route_command $route_directive $route_tns_cleanup
  }
  write_checkpoint -force [file join $experiment_dir routed.dcp]

  set timing_summary_path [file join $experiment_dir timing_summary.rpt]
  set timing_paths_path [file join $experiment_dir timing_paths_top5.rpt]
  set utilization_path [file join $experiment_dir utilization.rpt]
  set power_path [file join $experiment_dir power.rpt]
  set route_status_path [file join $experiment_dir route_status.rpt]

  report_timing_summary -file $timing_summary_path
  report_timing -delay_type max -max_paths 5 -nworst 5 -sort_by group -file $timing_paths_path
  report_utilization -file $utilization_path
  report_power -file $power_path
  report_route_status -file $route_status_path

  lassign [parse_timing_summary [read_text $timing_summary_path]] wns tns whs ths
  lassign [parse_utilization [read_text $utilization_path]] lut lut_mem ff dsp bram
  set power [parse_power [read_text $power_path]]

  set worst_path [lindex [get_timing_paths -delay_type max -max_paths 1 -nworst 1] 0]
  set source NA
  set destination NA
  set data_delay NA
  set logic_delay NA
  set route_delay NA
  set route_percent NA
  set logic_levels NA
  if {$worst_path ne ""} {
    set source [get_property STARTPOINT_PIN $worst_path]
    set destination [get_property ENDPOINT_PIN $worst_path]
    set data_delay [get_property DATAPATH_DELAY $worst_path]
    set logic_delay [get_property DATAPATH_LOGIC_DELAY $worst_path]
    set route_delay [get_property DATAPATH_NET_DELAY $worst_path]
    set logic_levels [get_property LOGIC_LEVELS $worst_path]
    if {$data_delay > 0.0} {
      set route_percent [format "%.2f" [expr {100.0 * $route_delay / $data_delay}]]
    }
  }

  set route_errors NA
  set route_status_text [read_text $route_status_path]
  regexp {# of nets with routing errors\.+\s*:\s*([0-9]+)} $route_status_text -> route_errors

  set unrouted_nets NA
  set partially_routed_nets NA
  catch { set unrouted_nets [llength [get_nets -hier -filter {ROUTE_STATUS == UNROUTED}]] }
  catch { set partially_routed_nets [llength [get_nets -hier -filter {ROUTE_STATUS == PARTIAL}]] }

  set run_end [clock seconds]
  set runtime_seconds [expr {$run_end - $run_start}]
  set runtime_hms [format_duration $runtime_seconds]

  set header "experiment,opt,place,pre_phys,route,route_tns_cleanup,post_phys,setup_wns_ns,setup_tns_ns,hold_whs_ns,hold_ths_ns,data_path_delay_ns,logic_delay_ns,route_delay_ns,route_delay_percent,logic_levels,lut,lut_memory,ff,dsp,bram,power_w,runtime_seconds,runtime_hms,route_errors,unrouted_nets,partially_routed_nets,source,destination"
  set values [list \
    $experiment_name $opt_directive $place_directive $pre_phys_directive \
    $route_directive $route_tns_cleanup $post_phys_directive \
    $wns $tns $whs $ths $data_delay $logic_delay $route_delay $route_percent \
    $logic_levels $lut $lut_mem $ff $dsp $bram $power $runtime_seconds \
    $runtime_hms $route_errors $unrouted_nets $partially_routed_nets \
    $source $destination]
  set quoted_values {}
  foreach value $values { lappend quoted_values [csv_quote $value] }
  set row [join $quoted_values ,]
  write_text [file join $experiment_dir metrics.csv] "$header\n$row\n"

  set global_csv [file join $sweep_root results.csv]
  set needs_header [expr {![file exists $global_csv] || [file size $global_csv] == 0}]
  set global_fd [open $global_csv a]
  if {$needs_header} { puts $global_fd $header }
  puts $global_fd $row
  close $global_fd

  set completion_text "PASS\nfinished_epoch=$run_end\nruntime_seconds=$runtime_seconds\n"
  write_text $completion_file $completion_text
} error_message error_options]} {
  set run_end [clock seconds]
  set failure_text "FAIL\nexperiment=$experiment_name\nerror=$error_message\n"
  append failure_text "error_info=[dict get $error_options -errorinfo]\n"
  append failure_text "runtime_seconds=[expr {$run_end - $run_start}]\n"
  write_text [file join $experiment_dir FAILED.txt] $failure_text
  puts stderr $failure_text
  exit 1
}

puts "Directive sweep experiment $experiment_name completed successfully."
exit 0
