# Four fresh OOC routed comparisons with identical 60-bit inputs and IO registers.
# Arguments: source snapshot, output directory.
if {$argc != 2} {error "Expected source snapshot and run directory"}
set source_root [file normalize [lindex $argv 0]]
set out [file normalize [lindex $argv 1]]
cd $source_root
set part_name xc7vx485tffg1761-2
set period 6.667
set fd [open [file join $out timing.csv] w]
puts $fd "kind,impl,core_cycles,wrapper_extra_cycles,reg_to_reg_wns_ns,reg_to_reg_whs_ns,data_path_delay_ns,startpoint,endpoint,clock_site"
flush $fd
foreach kind {0 1} {
  foreach impl {0 1} {
    set tag [format "kind%d_impl%d" $kind $impl]
    set dir [file join $out $tag]
    file mkdir $dir
    puts "KARATSUBA_BENCH_START $tag [clock format [clock seconds]]"
    create_project -in_memory -part $part_name $tag
    set_param general.maxThreads 4
    read_verilog -sv [list rtl/params_pkg.sv rtl/intmul_64x64_24x17.sv rtl/intmul_60x60_karatsuba4_experimental.sv rtl/wlmont_round16.sv rtl/mont_mul_wl.sv sim/mont_mul_wl_karatsuba14_experimental.sv sim/wl_karatsuba_bench_top.sv]
    set xdc [file join $dir compare.xdc]
    set f [open $xdc w]
    puts $f "create_clock -name clk -period $period \[get_ports clk\]"
    puts $f {set_input_delay -clock clk 1.000 [get_ports {a[*] b[*] in_valid rst_n}]}
    puts $f {set_output_delay -clock clk 1.000 [get_ports {y[*] out_valid}]}
    close $f
    read_xdc $xdc
    synth_design -top wl_karatsuba_bench_top -part $part_name -mode out_of_context -generic [list BENCH_KIND=$kind INT_IMPL=$impl]
    set clock_site [lindex [lsort [get_sites -filter {SITE_TYPE == BUFGCTRL}]] 0]
    if {$clock_site eq ""} {error "No global clock site found"}
    set_property HD.CLK_SRC $clock_site [get_ports clk]
    report_utilization -file [file join $dir synth_utilization.rpt]
    report_utilization -hierarchical -file [file join $dir synth_hierarchy.rpt]
    write_checkpoint -force [file join $dir synth.dcp]
    opt_design
    place_design
    phys_opt_design
    route_design
    report_utilization -file [file join $dir route_utilization.rpt]
    report_utilization -hierarchical -file [file join $dir route_hierarchy.rpt]
    set kernel [get_cells -hier -filter {NAME =~ *u_kernel}]
    if {[llength $kernel]!=1} {error "Kernel hierarchy is ambiguous: $kernel"}
    report_utilization -cells $kernel -file [file join $dir kernel_route_utilization.rpt]
    report_timing_summary -delay_type min_max -check_timing_verbose -report_unconstrained -file [file join $dir route_timing.rpt]
    set regs [all_registers]
    report_timing -from $regs -to $regs -delay_type max -max_paths 10 -file [file join $dir internal_paths.rpt]
    report_timing -from $regs -to $regs -delay_type min -max_paths 10 -file [file join $dir hold_paths.rpt]
    report_route_status -file [file join $dir route_status.rpt]
    report_drc -file [file join $dir route_drc.rpt]
    write_checkpoint -force [file join $dir routed.dcp]
    set path [get_timing_paths -from $regs -to $regs -delay_type max -max_paths 1]
    set hp [get_timing_paths -from $regs -to $regs -delay_type min -max_paths 1]
    if {[llength $path]!=1 || [llength $hp]!=1} {error "Missing timing path"}
    set slack [get_property SLACK $path]
    set hslack [get_property SLACK $hp]
    set lat [expr {$kind==0 ? 4 : 14}]
    puts $fd "$kind,$impl,$lat,2,$slack,$hslack,[get_property DATAPATH_DELAY $path],[get_property STARTPOINT_PIN $path],[get_property ENDPOINT_PIN $path],$clock_site"
    flush $fd
    puts "KARATSUBA_BENCH_DONE $tag LAT=$lat WNS=$slack WHS=$hslack [clock format [clock seconds]]"
    close_project
  }
}
close $fd
puts "WL_KARATSUBA_BENCH_PASS"