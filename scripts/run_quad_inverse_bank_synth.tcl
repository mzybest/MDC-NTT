# Sequential micro-synthesis comparison for C_NTT banking alternatives.
set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir ..]]
set report_dir [file join $repo_root reports quad_inverse_audit bank_synth]
set part_name xc7vx485tffg1761-2
set period_ns 6.667
file mkdir $report_dir

set designs [list \
  [list bank_2x2048x64_top bank_2x2048x64] \
  [list bank_4x1024x64_top bank_4x1024x64] \
]

set summary_rows {}
foreach design $designs {
  set top_name [lindex $design 0]
  set tag [lindex $design 1]
  set design_dir [file join $report_dir $tag]
  file mkdir $design_dir

  create_project -in_memory -part $part_name
  set_property target_language Verilog [current_project]
  read_verilog -sv [list \
    [file join $repo_root rtl top_data_bram.sv] \
    [file join $repo_root sim bank_layout_micro_synth.sv] \
  ]
  synth_design -top $top_name -part $part_name -flatten_hierarchy none
  create_clock -name clk -period $period_ns [get_ports clk]

  report_utilization -file [file join $design_dir utilization.rpt]
  report_utilization -hierarchical -hierarchical_depth 4 \
      -file [file join $design_dir utilization_hierarchical.rpt]
  catch {report_ram_utilization -file [file join $design_dir ram_utilization.rpt]}
  report_timing_summary -file [file join $design_dir timing_summary.rpt]
  write_checkpoint -force [file join $design_dir ${top_name}_synth.dcp]

  set ramb36_count [llength [get_cells -hier -filter {REF_NAME == RAMB36E1}]]
  set ramb18_count [llength [get_cells -hier -filter {REF_NAME == RAMB18E1}]]
  set lut_count [llength [get_cells -hier -filter {REF_NAME =~ LUT*}]]
  set ff_count [llength [get_cells -hier -filter {REF_NAME =~ FD*}]]
  lappend summary_rows [list $tag $ramb36_count $ramb18_count $lut_count $ff_count]
  close_project
}

set summary_path [file join $report_dir summary.csv]
set fd [open $summary_path w]
puts $fd "design,ramb36e1,ramb18e1,block_ram_tile_equiv,lut_cells,ff_cells"
foreach row $summary_rows {
  lassign $row tag ramb36_count ramb18_count lut_count ff_count
  set tile_equiv [expr {$ramb36_count + 0.5 * $ramb18_count}]
  puts $fd "$tag,$ramb36_count,$ramb18_count,$tile_equiv,$lut_count,$ff_count"
}

lassign [lindex $summary_rows 0] tag2 ramb36_2 ramb18_2 lut_2 ff_2
lassign [lindex $summary_rows 1] tag4 ramb36_4 ramb18_4 lut_4 ff_4
set tile_2 [expr {$ramb36_2 + 0.5 * $ramb18_2}]
set tile_4 [expr {$ramb36_4 + 0.5 * $ramb18_4}]
puts $fd "delta_4x1024_minus_2x2048,[expr {$ramb36_4-$ramb36_2}],[expr {$ramb18_4-$ramb18_2}],[expr {$tile_4-$tile_2}],[expr {$lut_4-$lut_2}],[expr {$ff_4-$ff_2}]"
close $fd

set meta [open [file join $report_dir config.txt] w]
puts $meta "vivado=[version -short]"
puts $meta "part=$part_name"
puts $meta "period_ns=$period_ns"
puts $meta "tops=bank_2x2048x64_top bank_4x1024x64_top"
puts $meta "rtl=rtl/top_data_bram.sv sim/bank_layout_micro_synth.sv"
close $meta

puts "Bank micro-synthesis complete: $summary_path"
exit 0
