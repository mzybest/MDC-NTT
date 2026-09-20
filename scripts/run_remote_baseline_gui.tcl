# Run from Vivado's Tools > Run Tcl Script on the remote workstation.
# This builds the EXISTING dual-forward baseline, not the proposed 4-path top.
# No Windows shell commands are used. Existing RTL and build scripts are reused.
namespace eval ::mdc_remote {
  variable launcher_dir [file dirname [file normalize [info script]]]
  variable root [file normalize [file join $launcher_dir ..]]
  variable output_root ""
}

proc ::mdc_remote::run {} {
  variable launcher_dir
  variable root
  variable output_root
  set part xc7vx485tffg1761-2
  set period 6.667
  if {[llength [get_parts -quiet $part]] != 1} {
    error "Required device $part is unavailable in this Vivado installation."
  }
  if {[llength [get_projects -quiet]] != 0} {
    error "Close the existing project first; this launcher must not alter it."
  }
  set tag "remote_baseline_[clock format [clock seconds] -format %Y%m%d_%H%M%S]"
  set output_root [file join $root reports dual_forward_dsp_reduction $tag]
  if {[file exists $output_root]} {
    error "Refusing to overwrite existing run: $output_root"
  }
  file mkdir $output_root
  set fd [open [file join $output_root remote_run.txt] w]
  puts $fd "host=[info hostname]"
  puts $fd "vivado=[version -short]"
  puts $fd "source_root=$root"
  puts $fd "top=poly_mul_top_dual_forward"
  puts $fd "configuration=natural_ab_raw_pre_shared"
  puts $fd "part=$part"
  puts $fd "target_period_ns=$period"
  puts $fd "implementation_period_ns=6.000"
  puts $fd "scope=existing baseline; no dynamic four-path reconstruction"
  puts $fd "comparison=tool-version-specific; not interchangeable with Vivado 2026.1"
  close $fd
  set_param general.maxThreads 4

  # Existing batch scripts end with exit 0. Suppress only successful exits while
  # sourcing them so synthesis can be followed by implementation in this GUI.
  # Always restore the original command, including when either build fails.
  rename ::exit ::mdc_remote::saved_exit
  proc ::exit {{code 0}} {
    if {$code != 0} { error "Build script requested exit $code" }
    return
  }
  set outcome [catch {
    set argc 4
    set argv [list natural_ab_raw_pre_shared $part $period "$tag/synth"]
    source [file join $launcher_dir run_synth_dual_forward_dsp_reduction.tcl]
    close_design
    set argc 4
    set argv [list "$tag/synth" "$tag/impl" $period 6.000]
    source [file join $launcher_dir run_impl_bram_ac_overconstraint.tcl]
  } detail options]
  rename ::exit {}
  rename ::mdc_remote::saved_exit ::exit

  set fd [open [file join $output_root status.txt] w]
  if {$outcome} {
    puts $fd "FAILED"
    puts $fd $detail
    if {[dict exists $options -errorinfo]} {
      puts $fd [dict get $options -errorinfo]
    }
  } else {
    puts $fd "COMPLETED"
    puts $fd "Review impl/timing_signoff.rpt and utilization_signoff.rpt."
    puts $fd "Completion alone does not mean timing passed."
  }
  close $fd
  if {$outcome} { return -options $options $detail }
  puts "REMOTE_BASELINE_COMPLETED: $output_root"
}

::mdc_remote::run
