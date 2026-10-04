OUTPUT_ARCH(riscv)
ENTRY(_reset)
MEMORY { ROM (rx) : ORIGIN = 0, LENGTH = 16K
         RAM (rw) : ORIGIN = 0x10000000, LENGTH = 8K }
SECTIONS {
 .vectors : { KEEP(*(.vectors)) } > ROM
 .text : { *(.text.start) *(.text*) *(.rodata*) . = ALIGN(4); } > ROM
 .data : { _data_start = .; *(.data*) *(.sdata*) . = ALIGN(4); _data_end = .; } > RAM AT>ROM
 _data_load = LOADADDR(.data);
 .bss (NOLOAD) : { _bss_start = .; *(.bss*) *(.sbss*) *(COMMON) . = ALIGN(4); _bss_end = .; } > RAM
 __global_pointer$ = ORIGIN(RAM) + 0x800;
 _stack_top = ORIGIN(RAM) + LENGTH(RAM);
 ASSERT(_bss_end <= _stack_top - 2048, "RAM must leave 2 KiB for stack")
}
