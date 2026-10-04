#!/bin/bash
set -euo pipefail
test "$(id -un)" = builder
test -w /home/builder/ebaz4205/petalinux/project-spec/configs/config
test -w /home/builder/src/adi-linux-2020.1/Makefile
for tool in gcc g++ make python python3 git rsync gawk diffstat chrpath socat cpio unzip texi2any xterm autoconf automake libtool file bison flex pax; do
    command -v "$tool" >/dev/null
done
tmp=$(mktemp -d)
trap 'rm -f "$tmp/hello.c" "$tmp/hello64" "$tmp/hello32"; rmdir "$tmp"' EXIT
printf 'int main(void) { return 0; }\n' > "$tmp/hello.c"
gcc "$tmp/hello.c" -o "$tmp/hello64"
gcc -m32 "$tmp/hello.c" -o "$tmp/hello32"
"$tmp/hello64"
"$tmp/hello32"
grep -F 'CONFIG_SUBSYSTEM_COMPONENT_LINUX__KERNEL_NAME_EXT_LOCAL_SRC_PATH="/home/builder/src/adi-linux-2020.1"' /home/builder/ebaz4205/petalinux/project-spec/configs/config
patch -d /home/builder/src/adi-linux-2020.1 -p1 --dry-run --reverse < /home/builder/ebaz4205/petalinux/project-spec/meta-user/recipes-kernel/linux/linux-xlnx/0001-Backported-bugfix-for-ADF435x-powerdown.patch
echo 'Host dependencies, permissions, kernel source and patch checks passed.'
if [ ! -f /home/builder/tools/petalinux-2020.2.2/settings.sh ]; then
    echo 'PetaLinux tools are not installed yet; a system build has not run.'
fi
