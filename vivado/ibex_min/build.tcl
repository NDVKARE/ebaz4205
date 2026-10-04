set here [file dirname [file normalize [info script]]]
cd $here
create_project ibex_min $here/project -part xc7z010clg400-1 -force
create_bd_design ibex_ps
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7
set_property -dict [list CONFIG.PCW_USE_M_AXI_GP0 {1} CONFIG.PCW_EN_CLK0_PORT {1} CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} CONFIG.PCW_EN_CLK1_PORT {1} CONFIG.PCW_FPGA1_PERIPHERAL_FREQMHZ {25} CONFIG.PCW_EN_RST1_PORT {1} CONFIG.PCW_EN_CLK2_PORT {0} CONFIG.PCW_EN_CLK3_PORT {0} CONFIG.PCW_UIPARAM_DDR_BUS_WIDTH {16 Bit} CONFIG.PCW_UIPARAM_DDR_MEMORY_TYPE {DDR 3 (Low Voltage)} CONFIG.PCW_UIPARAM_DDR_PARTNO {MT41K128M16 JT-125} CONFIG.PCW_UART1_PERIPHERAL_ENABLE {1} CONFIG.PCW_UART1_UART1_IO {MIO 24 .. 25} CONFIG.PCW_SD0_PERIPHERAL_ENABLE {1} CONFIG.PCW_SD0_SD0_IO {MIO 40 .. 45}] [get_bd_cells ps7]
# EBAZ4205 onboard 8-bit NAND: use the board's original PS configuration.
# Generate NAND MIO mux, SMC clock/timing and the NAND peripheral in the HDF.
set_property -dict [list CONFIG.PCW_NAND_PERIPHERAL_ENABLE {1} CONFIG.PCW_NAND_NAND_IO {MIO 0 2.. 14} CONFIG.PCW_NAND_GRP_D8_ENABLE {0} CONFIG.PCW_SMC_PERIPHERAL_FREQMHZ {100}] [get_bd_cells ps7]
# Conservative asynchronous timing at 100 MHz (10 ns per cycle).
# U-Boot preserves these FSBL timings instead of its fixed 50 MHz defaults.
set_property -dict [list CONFIG.PCW_NAND_CYCLES_T_RC {10} CONFIG.PCW_NAND_CYCLES_T_WC {10} CONFIG.PCW_NAND_CYCLES_T_WP {5} CONFIG.PCW_NAND_CYCLES_T_REA {4} CONFIG.PCW_NAND_CYCLES_T_RR {4} CONFIG.PCW_NAND_CYCLES_T_AR {4} CONFIG.PCW_NAND_CYCLES_T_CLR {2}] [get_bd_cells ps7]
create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddrx_rtl:1.0 DDR
connect_bd_intf_net [get_bd_intf_ports DDR] [get_bd_intf_pins ps7/DDR]
create_bd_intf_port -mode Master -vlnv xilinx.com:display_processing_system7:fixedio_rtl:1.0 FIXED_IO
connect_bd_intf_net [get_bd_intf_ports FIXED_IO] [get_bd_intf_pins ps7/FIXED_IO]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_protocol_converter:2.1 bridge
set_property -dict [list CONFIG.SI_PROTOCOL {AXI3} CONFIG.MI_PROTOCOL {AXI4LITE} CONFIG.DATA_WIDTH {32} CONFIG.ADDR_WIDTH {32} CONFIG.ID_WIDTH {12}] [get_bd_cells bridge]
connect_bd_intf_net [get_bd_intf_pins ps7/M_AXI_GP0] [get_bd_intf_pins bridge/S_AXI]
create_bd_intf_port -mode Master -vlnv xilinx.com:interface:aximm_rtl:1.0 M_AXI
set_property -dict [list CONFIG.PROTOCOL {AXI4LITE} CONFIG.DATA_WIDTH {32} CONFIG.ADDR_WIDTH {32} CONFIG.FREQ_HZ {25000000}] [get_bd_intf_ports M_AXI]
connect_bd_intf_net [get_bd_intf_pins bridge/M_AXI] [get_bd_intf_ports M_AXI]
create_bd_port -dir O -type clk clk25
set_property -dict [list CONFIG.FREQ_HZ {25000000} CONFIG.ASSOCIATED_BUSIF {M_AXI} CONFIG.ASSOCIATED_RESET {resetn}] [get_bd_ports clk25]
connect_bd_net [get_bd_pins ps7/FCLK_CLK1] [get_bd_ports clk25] [get_bd_pins bridge/aclk] [get_bd_pins ps7/M_AXI_GP0_ACLK]
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 reset_sync
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 one
create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 zero
set_property CONFIG.CONST_VAL 0 [get_bd_cells zero]
connect_bd_net [get_bd_pins one/dout] [get_bd_pins reset_sync/dcm_locked] [get_bd_pins reset_sync/aux_reset_in]
connect_bd_net [get_bd_pins zero/dout] [get_bd_pins reset_sync/mb_debug_sys_rst]
connect_bd_net [get_bd_pins ps7/FCLK_CLK1] [get_bd_pins reset_sync/slowest_sync_clk]
connect_bd_net [get_bd_pins ps7/FCLK_RESET1_N] [get_bd_pins reset_sync/ext_reset_in]
create_bd_port -dir O -type rst resetn
connect_bd_net [get_bd_pins reset_sync/peripheral_aresetn] [get_bd_ports resetn] [get_bd_pins bridge/aresetn]
create_bd_addr_seg -range 0x2000 -offset 0x43C00000 [get_bd_addr_spaces ps7/Data] [get_bd_addr_segs M_AXI/Reg] SCMI
validate_bd_design
if {[get_property CONFIG.C_AUX_RESET_HIGH [get_bd_cells reset_sync]] != 0} {
  error "aux_reset_in tied high requires active-low auxiliary reset"
}
save_bd_design
generate_target all [get_files ibex_ps.bd]
make_wrapper -files [get_files ibex_ps.bd] -top
set wrapper $here/project/ibex_min.srcs/sources_1/bd/ibex_ps/hdl/ibex_ps_wrapper.v
add_files $wrapper
# Generate a board top from the native PS wrapper's actual port declarations.
set f [open $wrapper r]; set contents [read $f]; close $f
set ports {}; set wires {}; set connections {}
foreach line [split $contents "\n"] {
  if {[regexp {^\s*(input|output|inout)\s+(\[[^\]]+\])?\s*(\w+)\s*;} $line -> direction width name]} {
    if {$direction eq "inout"} {lappend ports "    inout wire $width $name"} else {lappend wires "    wire $width $name;"}
    lappend connections "        .${name}($name)"
  }
}
lappend ports "    output wire led6_green_n" "    output wire led6_red_n" {    output wire [3:0] data_gpio}
set top "module ibex_min_top (\n[join $ports ,\n]\n);\n[join $wires \n]\n    ibex_ps_wrapper ps (\n[join $connections ,\n]\n    );\n    ibex_soc soc (\n        .clk(clk25), .resetn(resetn), .led6_green_n(led6_green_n), .led6_red_n(led6_red_n), .data_gpio(data_gpio), .cpu_fault()"
foreach signal {awaddr awvalid awready wdata wstrb wvalid wready bresp bvalid bready araddr arvalid arready rdata rresp rvalid rready} {append top ",\n        .s_axi_${signal}(M_AXI_$signal)"}
append top "\n    );\nendmodule\n"
set f [open $here/ibex_min_top.v w]; puts $f $top; close $f
add_files [list $here/ibex_min_top.v $here/ibex_cpu.v $here/rtl/ibex_soc.v $here/rtl/ibex_shared_ram.v $here/firmware.hex]
set_property file_type {Memory Initialization Files} [get_files *firmware.hex]
add_files -fileset constrs_1 $here/ibex_min.xdc
set_property top ibex_min_top [current_fileset]
set_property file_type SystemVerilog [get_files *ibex_cpu.v]
update_compile_order -fileset sources_1
synth_design -top ibex_min_top -part xc7z010clg400-1
write_checkpoint -force $here/ibex_min_synth.dcp
report_utilization -hierarchical -file $here/utilization_synth.rpt
opt_design
place_design
route_design
report_timing_summary -file $here/timing_summary.rpt
report_drc -file $here/drc.rpt
report_utilization -hierarchical -file $here/utilization.rpt
write_checkpoint -force $here/ibex_min_routed.dcp
write_bitstream -force $here/ibex_min.bit
write_hwdef -force -file $here/ibex_min.hwdef
write_sysdef -hwdef $here/ibex_min.hwdef -bitfile $here/ibex_min.bit -file $here/ibex_min.hdf -force
