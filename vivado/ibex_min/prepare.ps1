$ErrorActionPreference='Stop'
$baseDir=$PSScriptRoot
$repoDir=Join-Path $baseDir 'vendor/ibex'
$gcc='C:/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-gcc.exe'
$objcopy='C:/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-objcopy.exe'
$sv2v=Join-Path $baseDir '../../tools/sv2v/sv2v-Windows/sv2v.exe'
Push-Location $baseDir
try {
  & $gcc -march=rv32i_zicsr -mabi=ilp32 -Os -ffreestanding -fno-builtin -nostdlib -msmall-data-limit=0 '-Wl,--no-relax' '-Wl,-Map=firmware.map' -T firmware/link.ld firmware/start.S firmware/server.c -o firmware.elf
  if($LASTEXITCODE) {throw 'Firmware build failed'}
  & $objcopy -O binary firmware.elf firmware.bin
  if($LASTEXITCODE) {throw 'objcopy failed'}
  $binary=[IO.File]::ReadAllBytes((Join-Path $baseDir 'firmware.bin'))
  if($binary.Length -gt 16384) {throw 'Firmware exceeds ROM'}
  $romImage=New-Object byte[] 16384
  [Array]::Copy($binary,$romImage,$binary.Length)
  $hex=for($i=0;$i -lt 16384;$i+=4){'{0:x8}' -f [BitConverter]::ToUInt32($romImage,$i)}
  [IO.File]::WriteAllLines((Join-Path $baseDir 'firmware.hex'),[string[]]$hex)
  $rtlFiles=Get-ChildItem (Join-Path $repoDir 'rtl') -Filter '*.sv' | Where-Object {$_.Name -notin @('ibex_pkg.sv','ibex_top.sv','ibex_lockstep.sv','ibex_register_file_ff.sv','ibex_register_file_latch.sv','ibex_top_tracing.sv','ibex_tracer.sv','ibex_tracer_pkg.sv')} | ForEach-Object {$_.FullName}
  & $sv2v -D SYNTHESIS -D FPGA_XILINX -I "$repoDir/rtl" -I "$repoDir/vendor/lowrisc_ip/ip/prim/rtl" -I "$repoDir/vendor/lowrisc_ip/dv/sv/dv_utils" "$repoDir/rtl/ibex_pkg.sv" @rtlFiles "$baseDir/rtl/ibex_cpu.sv" --top=ibex_cpu --write="$baseDir/ibex_cpu.v"
  if($LASTEXITCODE) {throw 'sv2v failed'}
  Write-Output ('Firmware: {0} bytes, ROM: 16 KiB, Ibex pinned at 38da151a251de5b13afeedf9c5947707f87c5992' -f $binary.Length)
} finally {Pop-Location}
