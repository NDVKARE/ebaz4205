if {[catch {
set here [file dirname [file normalize [info script]]]
cd $here
set app_dir $here/fsbl_new
if {[llength $argv] > 0} {
    set app_dir [file normalize [lindex $argv 0]]
}
set hw_file $here/ibex_min.hdf
if {[llength $argv] > 1} {
    set hw_file [file normalize [lindex $argv 1]]
}
hsi::open_hw_design $hw_file
puts "PROCESSORS: [hsi::get_cells -filter {IP_TYPE == PROCESSOR}]"
# Reuse Vivado's PS init from this exact HDF. HSI 2015.1 can spend excessive
# time regenerating PS init with NAND; regeneration is unnecessary here.
set sdk_dir [file normalize [file join [file dirname [info nameofexecutable]] ../../..]]
set fsbl_hw_input $here/fsbl_hw_input
exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File $here/extract-fsbl-hw.ps1 \
    -Hdf $hw_file -Destination $fsbl_hw_input
# Application hooks run in an HSI child interpreter. Use a local copy of the
# SDK FSBL template so that hook itself copies the authoritative HDF PS init.
set repo_dir $here/fsbl_app_repo
set template_dir $repo_dir/lib/sw_apps/ebaz_fsbl
file mkdir $template_dir
foreach subdir {src data} {
    file copy -force $sdk_dir/data/embeddedsw/lib/sw_apps/zynq_fsbl/$subdir $template_dir
}
file rename -force $template_dir/data/zynq_fsbl.mss $template_dir/data/ebaz_fsbl.mss
set f [open $template_dir/data/zynq_fsbl.tcl r]
set template_code [read $f]
close $f
set copy_init {foreach filename {ps7_init.c ps7_init.h} {
    file copy -force $::env(EBAZ_FSBL_HW_INPUT)/$filename .
}}
set template_code [string map [list ::hsi::utils::generate_psinit $copy_init] $template_code]
set f [open $template_dir/data/ebaz_fsbl.tcl w]
puts -nonewline $f $template_code
close $f
file delete -force $template_dir/data/zynq_fsbl.tcl
set ::env(EBAZ_FSBL_HW_INPUT) $fsbl_hw_input
hsi::set_repo_path $repo_dir
hsi::generate_app -hw [hsi::current_hw_design] -os standalone -proc ps7_cortexa9_0 -app ebaz_fsbl -dir $app_dir -compile
set bsp_headers [glob $app_dir/*_bsp/ps7_cortexa9_0/include/xparameters.h]
if {[llength $bsp_headers] != 1} {error "Expected one FSBL BSP"}
set f [open [lindex $bsp_headers 0] r]
set parameters [read $f]
close $f
if {![regexp {#define XPAR_PS7_NAND_0_BASEADDR\s+0x} $parameters]} {
    error "FSBL BSP lacks NAND support; enable PS NAND in the hardware design"
}
# SDK 2015.1 emits fixed NAND cycle values in ps7_init.c even when the HDF
# contains the configured PCW_NAND_CYCLES_T_* values. Correct all silicon
# revision tables from that same HDF metadata, then rebuild the FSBL.
set f [open $fsbl_hw_input/ibex_ps.hwh r]
set ps_parameters [read $f]
close $f
set cycles 0
foreach {field shift width} {RC 0 4 WC 4 4 REA 8 3 WP 11 3 CLR 14 3 AR 17 3 RR 20 4} {
    set pattern [format {NAME="PCW_NAND_CYCLES_T_%s" VALUE="([0-9]+)"} $field]
    if {![regexp $pattern $ps_parameters -> value] || $value >= (1 << $width)} {
        error "Missing or invalid NAND timing: $field"
    }
    set cycles [expr {$cycles | ($value << $shift)}]
}
set f [open $app_dir/ps7_init.c r]
set init_code [read $f]
close $f
set cycle_word [format {0x%08XU} $cycles]
set count [regsub -all {EMIT_MASKWRITE\(0XE000E014,\s*0x00FFFFFFU\s*,\s*0x[[:xdigit:]]+U\)} $init_code \
    "EMIT_MASKWRITE(0XE000E014, 0x00FFFFFFU, $cycle_word)" init_code]
if {$count != 3} {error "Expected three NAND timing tables, found $count"}
set f [open $app_dir/ps7_init.c w]
puts -nonewline $f $init_code
close $f
set make $sdk_dir/gnuwin/bin/make.exe
set compiler $sdk_dir/gnu/arm/nt/bin/arm-xilinx-eabi-gcc.exe
puts "Applying HDF NAND timing $cycle_word to all three PS revision tables"
# Avoid same-second timestamp comparisons in the legacy Windows make tool.
file delete -force $app_dir/ps7_init.o $app_dir/executable.elf
puts [exec $make -C $app_dir CC=$compiler 2>@1]
puts "FSBL NAND support enabled: $app_dir/executable.elf"
} build_error]} {
    puts stderr "FSBL build failed: $build_error"
    exit 1
}
