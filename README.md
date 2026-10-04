# EBAZ4205 Ibex SCMI

Dự án tích hợp Ibex RISC-V trong PL của EBAZ4205, firmware SCMI và U-Boot
`v2025.10` có các lệnh `ibexinit`, `pmu_gpio`, `pmu_clock` và
`jtag_sd_update`.

## Clone mã nguồn

U-Boot upstream được quản lý bằng Git submodule:

```bash
git clone --recurse-submodules https://github.com/NDVKARE/ebaz4205.git
cd ebaz4205
```

Nếu đã clone mà chưa lấy U-Boot:

```bash
git submodule update --init --recursive
```

Submodule `third_party/u-boot` được khóa tại U-Boot `v2025.10`. Các driver,
command, device tree và cấu hình riêng của dự án nằm trong
`vivado/ibex_min/uboot`.

## Build U-Boot tùy biến

Trong WSL Ubuntu có toolchain `arm-linux-gnueabihf-`:

```bash
bash vivado/ibex_min/uboot/build-client.sh
```

Kết quả được chép tới:

```text
vivado/ibex_min/uboot/u-boot-ibex.elf
```

Autoboot đang tắt bằng `CONFIG_BOOTDELAY=-1`, vì vậy bo dừng ở dấu nhắc
U-Boot sau khi khởi động.

Tài liệu kỹ thuật nằm trong `doc/vivado/ibex_min`.
