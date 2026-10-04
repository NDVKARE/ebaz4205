# Run from the Tcl Console of the open ibex_min project before rerunning synthesis.
set firmware_path [file normalize [file join [get_property DIRECTORY [current_project]] .. firmware.hex]]
if {![file exists $firmware_path]} {
    error "Firmware ROM file not found: $firmware_path"
}
if {[llength [get_files -quiet $firmware_path]] == 0} {
    add_files -fileset sources_1 -norecurse $firmware_path
}
set_property file_type {Memory Initialization Files} [get_files $firmware_path]
set_property used_in_synthesis true [get_files $firmware_path]
update_compile_order -fileset sources_1
puts "Firmware registered for synthesis: $firmware_path"
