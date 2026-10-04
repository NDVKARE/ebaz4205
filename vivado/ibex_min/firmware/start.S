.section .vectors,"ax"
.globl _reset
.org 0
j trap
.org 0x2c
# mtvec vectored: machine external interrupt cause 11 enters at 4*11.
j scmi_irq
.org 0x80
_reset:
j _start
.section .text.start,"ax"
_start:
.option push
.option norelax
la gp, __global_pointer$
.option pop
la sp, _stack_top
li t0, 1
# Ibex supports vectored mtvec: table base 0, mode 1.
csrw mtvec, t0
la t0, _data_load
la t1, _data_start
la t2, _data_end
1: bgeu t1,t2,2f
lw t3,0(t0)
sw t3,0(t1)
addi t0,t0,4
addi t1,t1,4
j 1b
2: la t1,_bss_start
la t2,_bss_end
3: bgeu t1,t2,4f
sw zero,0(t1)
addi t1,t1,4
j 3b
4: call main
j trap
trap:
li t0,0x30000014
csrr t1,mcause
sw t1,0(t0)
5: j 5b
