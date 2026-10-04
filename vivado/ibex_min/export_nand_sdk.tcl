# Export current PS metadata while implementation runs. This SDK-only HDF
# carries the previously available PL bitstream; FSBL generation uses the PS
# metadata. The final boot image uses the new build's bitstream and HDF.
set here [file dirname [file normalize [info script]]]
create_project -in_memory -part xc7z010clg400-1
write_sysdef -hwdef $here/project/ibex_min.srcs/sources_1/bd/ibex_ps/hdl/ibex_ps.hwdef \
    -bitfile $here/recovery_before_nand/ibex_min.bit -file $here/ibex_nand_sdk.hdf -force
