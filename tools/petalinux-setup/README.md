# EBAZ4205 PetaLinux preparation

The actual XSA files were exported by Vivado 2020.2. The checked-in Yocto
kernel recipe is also 2020.2; the original README's 2020.1 note is older.
Use **PetaLinux 2020.2.2** for this checkout. It is AMD's 2020.2 patch
release and still provides the Zynq (`arm`) platform used here.

Prepared environment: WSL2 distribution `PetaLinux-1804`, stored on
`E:\WSL\PetaLinux-1804`, running Ubuntu 18.04. WSL is a practical local
build environment; it is not one of the Linux host configurations listed
as supported in the PetaLinux 2020.2 guide. A successful build still needs
to be verified on the board.

Downloads are in `E:\WSL\PetaLinux-downloads`. The Ubuntu root filesystem
comes from Canonical and its SHA256 was checked against the published
SHA256SUMS. The ADI source archive is pinned to commit
`4d2388646b4c24b128336077ec55c8068418688a` (tag `adi-xilinx-2020.1`).
The original author's precise kernel revision is not recorded, so this
is a candidate replacement, not a verified reproduction of their kernel.
Downloaded ADI archive SHA256:
`c30f7efbdc66bb425bfeb67e476af5b867ea382d8caceb50c024c7a5b0f6959b`
(recorded locally for repeatability; not an upstream signed checksum).

The working copy is `/home/builder/ebaz4205/petalinux`, on the Linux
filesystem. The original project on E: is preserved. The working copy's
kernel path points to `/home/builder/src/adi-linux-2020.1`. Its ADF435x patch
is applied to this external source; build concurrency is limited to two
jobs for the 8 GB host.

Download `petalinux-v2020.2.2-final-installer.run` from AMD's official page:
https://www.amd.com/en/support/downloads/adaptive-socs-and-fpgas/embedded-software.html
and save it in `E:\WSL\PetaLinux-downloads`.

From PowerShell, install tools (interactive license prompts):

```powershell
wsl -d PetaLinux-1804 -u builder -- bash /mnt/e/EBAZ4205-PetaLinux-main/EBAZ4205-PetaLinux-main/tools/petalinux-setup/install-tools.sh
```

Then build and package:

```powershell
wsl -d PetaLinux-1804 -u builder -- bash /mnt/e/EBAZ4205-PetaLinux-main/EBAZ4205-PetaLinux-main/tools/petalinux-setup/build.sh
```

Build log: `/home/builder/ebaz4205/build.log`.
Outputs: `/home/builder/ebaz4205/petalinux/images/linux/BOOT.BIN`,
`boot.scr`, and `image.ub`. These outputs exist only after a successful
build. The bitstream packaged by the script is the one supplied with the
original hardware description; updated Vivado hardware must be imported
and its matching bitstream selected before packaging.
