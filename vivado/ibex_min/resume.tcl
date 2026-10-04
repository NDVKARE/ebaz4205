# Resume an already-generated native project without regenerating all IP.
set here [file dirname [file normalize [info script]]]
cd $here
open_project $here/project/ibex_min.xpr
source $here/fix_firmware_project.tcl
set f [open $here/build.tcl r]; set script [read $f]; close $f
set start [string first {set wrapper } $script]
if {$start < 0} {error "Missing implementation section"}
eval [string range $script $start end]
