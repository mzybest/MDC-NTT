set matches [get_parts -quiet xc7vx330t*]
if {[llength $matches] == 0} {
  puts "NO_XC7VX330T_PARTS"
} else {
  foreach part $matches {
    puts "VIRTEX7_PART=$part"
  }
}
exit 0
