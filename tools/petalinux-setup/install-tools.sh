#!/bin/bash
set -euo pipefail
installer=/mnt/e/WSL/PetaLinux-downloads/petalinux-v2020.2.2-final-installer.run
destination=/home/builder/tools/petalinux-2020.2.2
if [ "$(id -u)" -eq 0 ]; then
    echo 'Run as builder, not root.' >&2
    exit 1
fi
if [ ! -f "$installer" ]; then
    echo "Missing installer: $installer" >&2
    exit 1
fi
if [ -f "$destination/settings.sh" ]; then
    echo "PetaLinux already installed: $destination"
    exit 0
fi
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
# Interactive installer: review and accept the displayed license agreements.
bash "$installer" --dir "$destination" --platform arm
