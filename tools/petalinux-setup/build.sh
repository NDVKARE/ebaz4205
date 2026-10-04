#!/bin/bash
set -eo pipefail
tools_dir=/home/builder/tools/petalinux-2020.2.2
if [ ! -f "$tools_dir/settings.sh" ]; then
    echo 'Missing PetaLinux 2020.2. Install the official installer first.' >&2
    exit 1
fi
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
source "$tools_dir/settings.sh"
cd /home/builder/ebaz4205/petalinux
petalinux-config --silentconfig
petalinux-build 2>&1 | tee /home/builder/ebaz4205/build.log
petalinux-package --boot --fsbl images/linux/zynq_fsbl.elf --fpga project-spec/hw-description/blockdesign_1_wrapper.bit --u-boot images/linux/u-boot.elf --force
for output in BOOT.BIN boot.scr image.ub; do
    test -s "images/linux/$output"
done
echo 'Build complete: /home/builder/ebaz4205/petalinux/images/linux'
