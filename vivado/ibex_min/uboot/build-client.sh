#!/usr/bin/env bash
set -euo pipefail
here=$(cd -- "$(dirname -- "$0")" && pwd)
src=${1:-${IBEX_UBOOT_SOURCE:-$HOME/ebaz4205-build/u-boot-scmi}}
if [ ! -f "$src/Makefile" ]; then
    printf 'U-Boot source missing: %s\nRun tools/petalinux-setup/build-uboot.sh first.\n' "$src" >&2
    exit 1
fi
export CROSS_COMPILE=arm-linux-gnueabihf-
cd "$src"
# Start from the project defconfig and put generated files in out-ibex.
mkdir -p out-ibex
cp "$here/zynq_ebaz4205_defconfig" out-ibex/.config
cp "$here/ibex-mbox.c" drivers/mailbox/ibex-mbox.c
cp "$here/ibex-gpio.c" cmd/ibex-gpio.c
cp "$here/s2-reset.c" cmd/s2-reset.c
cp "$here/s2-reset-state.h" cmd/s2-reset-state.h
cp "$here/jtag-sd-update.c" cmd/jtag-sd-update.c
cp "$here/zynq-ebaz4205.dts" arch/arm/dts/zynq-ebaz4205.dts
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
    --enable MMC --enable DM_MMC --enable MMC_SDHCI --enable MMC_SDHCI_ZYNQ --enable CMD_MMC \
    --enable DOS_PARTITION --enable CMD_FAT --enable FS_FAT --enable FAT_WRITE \
    --enable CMD_LOADB \
    --enable NET --enable NETDEVICES --enable DM_ETH --enable ZYNQ_GEM \
    --enable PHYLIB --enable MII --enable PHY_REALTEK --enable DM_ETH_PHY \
    --enable CMD_DHCP --enable CMD_PING --enable CMD_MII --enable NET_RANDOM_ETHADDR \
    --disable SCMI_AGENT_SMCCC --disable FIT_SIGNATURE --disable CMD_ZYNQ_RSA --enable AUTOBOOT --disable USE_PREBOOT \
    --enable USE_BOOTCOMMAND --disable NET_LWIP --disable NO_NET
# Give the operator two seconds to interrupt automatic Linux boot.
./scripts/config --file out-ibex/.config --set-val BOOTDELAY 2
./scripts/config --file out-ibex/.config --set-str BOOTCOMMAND \
    'ibexinit; if fatload mmc 0:1 0x08000000 image.ub; then bootm 0x08000000; fi'
./scripts/config --file out-ibex/.config --set-str LOCALVERSION '-ibex-lazy'
make O=out-ibex olddefconfig
for option in MMC DM_MMC MMC_SDHCI_ZYNQ CMD_MMC DOS_PARTITION CMD_FAT FS_FAT FAT_WRITE CMD_LOADB; do
    grep -q "^CONFIG_${option}=y$" out-ibex/.config || {
        printf 'Required UART/SD option missing: CONFIG_%s\n' "$option" >&2
        exit 1
    }
done
make O=out-ibex DEVICE_TREE=zynq-ebaz4205 -j2
# Zynq Bootgen/FSBL expects the remade ELF with a single loadable payload.
# It is generated after u-boot-nodtb.bin and retains the configured commands.
grep -a -q bootm out-ibex/u-boot.elf
cp out-ibex/u-boot.elf "$here/u-boot-ibex.elf"
