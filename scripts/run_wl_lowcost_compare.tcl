# Same-device OOC synthesis and route comparison of three WL implementations.
# vivado -mode batch -source scripts/run_wl_lowcost_compare.tcl
set repo_root [file normalize [file join [file dirname [info script]] ..]]
cd $repo_root
set part_name xc7vx485tffg1761-2
set period 6.667
set report_root [file join $repo_root reports wl_lowcost_modmul vivado]
file mkdir $report_root
set summary [open [file join $report_root summary.csv] w]
puts $summary "impl,part,period_ns,dsp48,lut_primitives,ff_primitives,wns_ns"
flush $summary
foreach impl {0 1 2} {
  set dir [file join $report_root impl_$impl]
  file mkdir $dir
  create_project -in_memory -part $part_name wl_lowcost_$impl
  set_param general.maxThreads 4
  read_verilog -sv [list rtl/params_pkg.sv rtl/intmul_64x64_24x17.sv rtl/wlmont_round16.sv rtl/mont_mul_wl.sv]
  set xdc [file join $dir compare.xdc]
  set fd [open $xdc w]
  puts $fd "create_clock -name clk -period $period \[get_ports clk\]"
  puts $fd {set_input_delay -clock clk 1.000 [get_ports {a[*] b[*] in_valid rst_n}]}
  puts $fd {set_output_delay -clock clk 1.000 [get_ports {y[*] out_valid}]}
  close $fd
  read_xdc $xdc
  synth_design -top mont_mul_wl -part $part_name -mode out_of_context -generic REDUCTION_IMPL=$impl
  report_utilization -file [file join $dir synth_utilization.rpt]
  report_utilization -hierarchical -file [file join $dir synth_hierarchy.rpt]
  write_checkpoint -force [file join $dir synth.dcp]
  opt_design
  place_design
  phys_opt_design
  route_design
  report_utilization -file [file join $dir route_utilization.rpt]
  report_utilization -hierarchical -file [file join $dir route_hierarchy.rpt]
  report_timing_summary -delay_type min_max -check_timing_verbose -report_unconstrained -file [file join $dir route_timing.rpt]
  report_timing -max_paths 10 -file [file join $dir route_paths.rpt]
  report_drc -file [file join $dir route_drc.rpt]
  write_checkpoint -force [file join $dir routed.dcp]
  set dsp [llength [get_cells -hier -filter {REF_NAME == DSP48E1}]]
  set lut [llength [get_cells -hier -filter {REF_NAME =~ LUT*}]]
  set ff [llength [get_cells -hier -filter {REF_NAME =~ FD*}]]
  set wns [get_property SLACK [lindex [get_timing_paths -delay_type max -max_paths 1] 0]]
  puts $summary "$impl,$part_name,$period,$dsp,$lut,$ff,$wns"
  flush $summary
  puts "WL_LOWCOST_IMPL_DONE impl=$impl DSP=$dsp LUT=$lut FF=$ff WNS=$wns"
  close_project
}
close $summary
puts "WL_LOWCOST_COMPARE_PASS"
