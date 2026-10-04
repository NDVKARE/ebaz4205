#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
dpkg --add-architecture i386
apt-get update
apt-get install -y --no-install-recommends sudo ca-certificates curl wget git rsync locales build-essential gcc-multilib g++-multilib python python3 python3-pip gawk diffstat chrpath socat cpio unzip texinfo xterm autoconf automake libtool libtool-bin libncurses5-dev libssl-dev zlib1g-dev zlib1g:i386 libsdl1.2-dev libselinux1 net-tools iproute2 file bison flex pax screen bc u-boot-tools patch
locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8
if ! id builder >/dev/null 2>&1; then
    useradd -m -s /bin/bash builder
fi
printf '[user]\ndefault=builder\n' > /etc/wsl.conf
install -d -o builder -g builder /home/builder/ebaz4205 /home/builder/src /home/builder/tools
echo 'Ubuntu dependencies ready'
