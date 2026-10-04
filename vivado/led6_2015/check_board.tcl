open_hw
connect_hw_server -url localhost:3121
set targets [get_hw_targets]
puts "JTAG_TARGETS: $targets"
foreach target $targets {
    open_hw_target $target
    puts "JTAG_DEVICES: [get_hw_devices]"
    close_hw_target $target
}
disconnect_hw_server
close_hw
