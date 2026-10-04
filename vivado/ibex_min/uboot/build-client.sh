#!/usr/bin/env bash
set -euo pipefail
here=$(cd -- "$(dirname -- "$0")" && pwd)
src=${1:-/home/vund19/ebaz-dev/u-boot}
export CROSS_COMPILE=arm-linux-gnueabihf-
cd "$src"
# Preserve existing console config; put new build output in out-ibex.
mkdir -p out-ibex
cp out/.config out-ibex/.config
cp "$here/ibex-mbox.c" drivers/mailbox/ibex-mbox.c
cp "$here/ibex-gpio.c" cmd/ibex-gpio.c
cp "$here/s2-reset.c" cmd/s2-reset.c
cp "$here/s2-reset-state.h" cmd/s2-reset-state.h
cp "$here/jtag-sd-update.c" cmd/jtag-sd-update.c
cp "$here/ibex-scmi.dtsi" arch/arm/dts/ibex-scmi.dtsi
if ! grep -q 'ebaz_default_history' common/cli_readline.c; then
    patch --forward -p1 < "$here/cli-default-history.patch"
fi
if ! grep -q 'config IBEX_MBOX' drivers/mailbox/Kconfig; then
    cat >> drivers/mailbox/Kconfig <<'EOF'

config IBEX_MBOX
    bool "EBAZ4205 Ibex PL mailbox"
    depends on DM_MAILBOX
EOF
fi
grep -q 'CONFIG_IBEX_MBOX' drivers/mailbox/Makefile || printf '\nobj-$(CONFIG_IBEX_MBOX) += ibex-mbox.o\n' >> drivers/mailbox/Makefile
grep -q 'ibex-gpio.o' cmd/Makefile || printf '\nobj-$(CONFIG_CMD_SCMI) += ibex-gpio.o\n' >> cmd/Makefile
grep -q 's2-reset.o' cmd/Makefile || printf '\nobj-$(CONFIG_CMD_SCMI) += s2-reset.o\n' >> cmd/Makefile
grep -q 'jtag-sd-update.o' cmd/Makefile || printf '\nobj-$(CONFIG_CMD_SCMI) += jtag-sd-update.o\n' >> cmd/Makefile
grep -q 'ibex-scmi.dtsi' arch/arm/dts/zynq-ebaz4205.dts || printf '\n#include "ibex-scmi.dtsi"\n' >> arch/arm/dts/zynq-ebaz4205.dts
./scripts/config --file out-ibex/.config --enable DM_MAILBOX --enable IBEX_MBOX \
    --enable SCMI_FIRMWARE --enable SCMI_AGENT_MAILBOX --enable CMD_SCMI \
    --enable CYCLIC --enable EVENT --enable DM_GPIO --enable ZYNQ_GPIO \
    --enable CMD_NAND --enable NAND_ZYNQ --enable NAND_ZYNQ_USE_BOOTLOADER1_TIMINGS \
    --disable SCMI_AGENT_SMCCC --enable AUTOBOOT --disable USE_PREBOOT \
    --enable USE_BOOTCOMMAND --disable NET --disable NET_LWIP --enable NO_NET
# A negative delay disables autoboot and leaves the board at the U-Boot prompt.
./scripts/config --file out-ibex/.config --set-val BOOTDELAY -1
./scripts/config --file out-ibex/.config --set-str BOOTCOMMAND \
    'ibexinit; fatload mmc 0:1 0x03000000 image.ub; bootm 0x03000000'
./scripts/config --file out-ibex/.config --set-str LOCALVERSION '-ibex-lazy'
make O=out-ibex olddefconfig
make O=out-ibex DEVICE_TREE=zynq-ebaz4205 -j2
cp out-ibex/u-boot.elf "$here/u-boot-ibex.elf"
