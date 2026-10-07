# EBAZ4205 Ibex SCMI

Dự án tích hợp Ibex RISC-V trong PL của EBAZ4205, firmware SCMI và U-Boot
`v2025.10` có các lệnh `ibexinit`, `pmu_gpio`, `pmu_clock` và
`jtag_sd_update`.

## Clone mã nguồn

Repository chỉ giữ phần tùy biến dành cho EBAZ4205:

```bash
git clone https://github.com/NDVKARE/ebaz4205.git
cd ebaz4205
```

Các driver, command, device tree, patch và cấu hình riêng của dự án nằm
trong `vivado/ibex_min/uboot`. Script build tải U-Boot `v2025.10` (commit
`e50b1e8715011def8aff1588081a2649a2c6cd47`) vào
`$HOME/ebaz4205-build/u-boot-scmi`, bên ngoài repository.
Có thể đổi đường dẫn bằng biến `IBEX_UBOOT_SOURCE`.

## Build U-Boot tùy biến

Trong WSL Ubuntu có toolchain `arm-linux-gnueabihf-`:

```bash
bash tools/petalinux-setup/build-uboot.sh
```

Kết quả được chép tới:

```text
vivado/ibex_min/uboot/u-boot-ibex.elf
```

Autoboot chờ 2 giây; nhấn phím để vào dấu nhắc U-Boot. Nếu tải được
`image.ub` từ phân vùng FAT `mmc 0:1`, U-Boot khởi động Linux.

Hướng dẫn cập nhật `pmufw.bin` qua UART nằm trong
[`UART-SD.md`](vivado/ibex_min/uboot/UART-SD.md). Trên Windows, dùng
`tools/send-pmufw.ps1` để gửi YMODEM qua COM5.

Tài liệu kỹ thuật nằm trong `doc/vivado/ibex_min`.
