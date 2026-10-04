set here [file dirname [file normalize [info script]]]
cd $here
open_checkpoint $here/ibex_min_routed.dcp
foreach {port pin} {led6_green_n W13 led6_red_n W14 data_gpio[0] A20 data_gpio[1] H16 data_gpio[2] B19 data_gpio[3] B20} {
    set actual [get_property PACKAGE_PIN [get_ports $port]]
    if {$actual ne $pin} {error "Pin mismatch: $port expected $pin, got $actual"}
    if {[get_property IOSTANDARD [get_ports $port]] ne "LVCMOS33"} {error "Incorrect IOSTANDARD: $port"}
    puts "PASS pin: $port = $actual LVCMOS33"
}
if {[llength [get_cells -hier -filter {NAME =~ *led_rate_hz_reg*}]] != 7} {
    error "Expected seven rate register bits in routed hardware"
}
report_io -file $here/clock_rate_io.rpt
puts "PASS: clock rate register and all six output pins verified"
