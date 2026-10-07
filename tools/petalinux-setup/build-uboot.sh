#!/bin/bash
set -euo pipefail
here=$(cd -- "$(dirname -- "$0")" && pwd)
repo=$(cd -- "$here/../.." && pwd)
upstream=https://github.com/u-boot/u-boot.git
revision=e50b1e8715011def8aff1588081a2649a2c6cd47
source_dir=${IBEX_UBOOT_SOURCE:-$HOME/ebaz4205-build/u-boot-scmi}
if [ ! -d "$source_dir/.git" ]; then
    git clone --branch v2025.10 --depth 1 "$upstream" "$source_dir"
fi
test "$revision" = "$(git -C "$source_dir" rev-parse HEAD)"
# Build on Linux storage: version detection and make are slow on /mnt/e.
bash "$repo/vivado/ibex_min/uboot/build-client.sh" "$source_dir"
