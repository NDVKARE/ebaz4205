set here [file dirname [file normalize [info script]]]
create_project led6_2015 $here/project -part xc7z010clg400-1 -force
create_bd_design led6_ps
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7
set_property -dict [list CONFIG.PCW_USE_M_AXI_GP0 {0} CONFIG.PCW_EN_CLK0_PORT {1} CONFIG.PCW_EN_CLK1_PORT {0} CONFIG.PCW_EN_CLK2_PORT {0} CONFIG.PCW_EN_CLK3_PORT {0} CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {25} CONFIG.PCW_UIPARAM_DDR_BUS_WIDTH {16 Bit} CONFIG.PCW_UIPARAM_DDR_MEMORY_TYPE {DDR 3 (Low Voltage)} CONFIG.PCW_UIPARAM_DDR_PARTNO {MT41K128M16 JT-125}] [get_bd_cells ps7]
create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddrx_rtl:1.0 DDR
connect_bd_intf_net [get_bd_intf_ports DDR] [get_bd_intf_pins ps7/DDR]
create_bd_intf_port -mode Master -vlnv xilinx.com:display_processing_system7:fixedio_rtl:1.0 FIXED_IO
connect_bd_intf_net [get_bd_intf_ports FIXED_IO] [get_bd_intf_pins ps7/FIXED_IO]
set clk [create_bd_port -dir O -type clk clk25]
connect_bd_net $clk [get_bd_pins ps7/FCLK_CLK0]
validate_bd_design
save_bd_design
generate_target all [get_files led6_ps.bd]
make_wrapper -files [get_files led6_ps.bd] -top
add_files $here/project/led6_2015.srcs/sources_1/bd/led6_ps/hdl/led6_ps_wrapper.v
add_files [list $here/led6_blink.v $here/led6_top.v]
add_files -fileset constrs_1 $here/led6.xdc
set_property top led6_top [current_fileset]
update_compile_order -fileset sources_1
synth_design -top led6_top -part xc7z010clg400-1
opt_design
place_design
route_design
report_timing_summary -file $here/timing_summary.rpt
report_drc -file $here/drc.rpt
write_checkpoint -force $here/led6_top_routed.dcp
write_bitstream -force $here/led6_top.bit
write_hwdef -force -file $here/led6_top.hwdef
write_sysdef -hwdef $here/led6_top.hwdef -bitfile $here/led6_top.bit -file $here/led6_top.hdf -force
file copy -force $here/project/led6_2015.srcs/sources_1/bd/led6_ps/ip/led6_ps_ps7_0/ps7_init.tcl $here/ps7_init.tcl
