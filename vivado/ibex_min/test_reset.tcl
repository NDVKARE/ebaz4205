set here [file dirname [file normalize [info script]]]
cd $here
create_project reset_test $here/reset_test -part xc7z010clg400-1 -force
read_ip $here/project/ibex_min.srcs/sources_1/bd/ibex_ps/ip/ibex_ps_reset_sync_0/ibex_ps_reset_sync_0.xci
add_files -fileset sim_1 $here/tests/reset_tb.sv
set_property top reset_tb [get_filesets sim_1]
set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
launch_simulation
run all
close_sim
close_project
