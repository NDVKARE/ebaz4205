if {$argc != 5} {
    puts stderr "usage: jtag-copy-boot-to-sd.tcl <file> <data_addr> <desc_addr> <size> <crc32>"
    exit 2
}
set image_file [file normalize [lindex $argv 0]]
set data_addr [lindex $argv 1]
set desc_addr [lindex $argv 2]
set image_size [lindex $argv 3]
set image_crc [lindex $argv 4]

if {[catch {
    connect
    targets -set -filter {name =~ "ARM*#0"}
    stop
    mwr $desc_addr 0
    dow -data $image_file $data_addr
    mwr [expr {$desc_addr + 4}] 1
    mwr [expr {$desc_addr + 8}] $data_addr
    mwr [expr {$desc_addr + 12}] $image_size
    mwr [expr {$desc_addr + 16}] $image_crc
    mwr [expr {$desc_addr + 20}] [expr {(~$image_size) & 0xffffffff}]
    mwr $desc_addr 0x4a534455
    con
    disconnect
} transfer_error]} {
    puts stderr "JTAG transfer failed: $transfer_error"
    catch {con}
    catch {disconnect}
    exit 1
}
puts "JTAG transfer complete: $image_file ($image_size bytes, CRC32=$image_crc)"
exit 0
