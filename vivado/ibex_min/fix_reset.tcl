set here [file dirname [file normalize [info script]]]
cd $here
open_project $here/project/ibex_min.xpr
open_bd_design [get_files ibex_ps.bd]
set aux [get_bd_pins reset_sync/aux_reset_in]
disconnect_bd_net [get_bd_nets -of_objects $aux] $aux
connect_bd_net [get_bd_pins one/dout] $aux
validate_bd_design
if {[get_property CONFIG.C_AUX_RESET_HIGH [get_bd_cells reset_sync]] != 0} {
  error "aux_reset_in tied high requires active-low auxiliary reset"
}
save_bd_design
generate_target all [get_files ibex_ps.bd]
set f [open $here/build.tcl r]
set script [read $f]
close $f
set start [string first {set wrapper } $script]
eval [string range $script $start end]
