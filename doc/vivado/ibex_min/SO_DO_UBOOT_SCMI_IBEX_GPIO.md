# Sơ đồ U-Boot → SCMI → Ibex → GPIO → Response

Các đường dẫn trong tài liệu tính từ `vivado/ibex_min/`.
Mở Markdown Preview có hỗ trợ Mermaid để xem sơ đồ.

Xem thêm [sơ đồ SCMI Clock cho LED6 đỏ](SCMI_CLOCK_LED6.md).

Đã mở rộng GPIO0 (LED6) thành 5 ngõ ra: GPIO1..4 ở DATA1 chân 5..8.
Các ví dụ GPIO0 bên dưới vẫn áp dụng; dùng `pmu_gpio ID on/off/get` để chọn
ngõ ra. Xem [sơ đồ và ánh xạ nhiều GPIO](GPIO_DATA1.md).

## 1. Mối liên hệ các file khi build

```mermaid
flowchart TD
    FW["firmware/server.c + start.S + link.ld"] --> PREP["prepare.ps1"]
    CPU["vendor/ibex + rtl/ibex_cpu.sv"] --> PREP
    PREP --> HEX["firmware.hex<br/>Firmware chạy trên Ibex"]
    PREP --> CPUV["ibex_cpu.v"]
    HEX --> VIV["Vivado: build.tcl"]
    CPUV --> VIV
    RTL["rtl/ibex_soc.v<br/>rtl/ibex_shared_ram.v<br/>ibex_min_top.v + ibex_ps_bd.tcl"] --> VIV
    VIV --> BIT["ibex_min.bit<br/>Mạch PL + firmware trong ROM"]
    VIV --> HDF["ibex_min.hdf<br/>Thông tin cấu hình phần cứng"]
    HDF --> FSBUILD["SDK: create_fsbl.tcl"]
    FSBUILD --> FSBL["fsbl_new/executable.elf"]
    CUSTOM["uboot/ibex-gpio.c<br/>uboot/ibex-mbox.c<br/>uboot/ibex-scmi.dtsi"] --> SCRIPT["uboot/build-client.sh"]
    SCRIPT --> UB["Dự án U-Boot trong WSL<br/>Chép file, sửa cấu hình, build toàn bộ"]
    UB --> ELF["uboot/u-boot-ibex.elf"]
    FSBL --> PACK["Bootgen dùng boot.bif"]
    BIT --> PACK
    ELF --> PACK
    PACK --> BOOT["BOOT.BIN"]
```

`server.c` được biên dịch thành mã RISC-V chạy trên Ibex và nhúng vào bitstream.
`ibex-gpio.c` và `ibex-mbox.c` được biên dịch thành mã ARM chạy trong U-Boot.

`uboot/` ở đây chứa phần bổ sung cho Ibex. `build-client.sh` chép các file sang
dự án U-Boot đầy đủ, mặc định tại `/home/vund19/ebaz-dev/u-boot` trong WSL.
Script lấy cấu hình từ `out/.config`, sửa Kconfig/Makefile và DTS, build toàn bộ
U-Boot vào `out-ibex/`, rồi chép ELF về `uboot/u-boot-ibex.elf`.
Chạy script sẽ ghi đè các file Ibex tương ứng trong dự án U-Boot bằng bản ở đây.

## 2. Sơ đồ hệ thống khi chạy

```mermaid
flowchart TB
    subgraph PS["PS — ARM chạy U-Boot"]
        CMD["Console: pmu_gpio on/off/get"]
        GPIOCMD["uboot/ibex-gpio.c<br/>Tạo yêu cầu protocol 0x80"]
        SCMI["SCMI framework của U-Boot<br/>SCMI agent + mailbox transport"]
        DRV["uboot/ibex-mbox.c<br/>Gửi request, kiểm tra completion"]
        CMD --> GPIOCMD --> SCMI --> DRV
    end
    subgraph PL["PL — phần cứng trong bitstream"]
        SHM["rtl/ibex_shared_ram.v<br/>Shared memory: 0x43C01000<br/>Chứa request và response SCMI"]
        MBOX["rtl/ibex_soc.v<br/>Mailbox: 0x43C00000"]
        IBEX["Ibex CPU<br/>firmware/start.S + server.c"]
        REG["Thanh ghi GPIO0<br/>Mailbox + 0x10"]
        LED["LED6 xanh<br/>RTL đảo mức active-low"]
        MBOX -->|"Request gây ngắt"| IBEX
        SHM -->|"Đọc yêu cầu"| IBEX
        IBEX -->|"GPIO_SET / GPIO_GET"| REG
        REG --> LED
        IBEX -->|"Ghi response"| SHM
        IBEX -->|"Báo completion"| MBOX
    end
    SCMI -->|"Ghi request qua AXI"| SHM
    DRV -->|"Ghi request doorbell"| MBOX
    MBOX -->|"U-Boot polling completion"| DRV
    SHM -->|"Đọc response qua AXI"| SCMI
    SCMI -->|"Status và giá trị"| GPIOCMD
    GPIOCMD -->|"In kết quả"| CMD
```

SCMI là định dạng và quy tắc trao đổi message. Shared memory chứa nội dung
message; mailbox báo có yêu cầu hoặc đã xử lý xong.

`uboot/ibex-scmi.dtsi` khai báo địa chỉ và nối SCMI agent với mailbox/shared
memory. Node SCMI có `status = "disabled"` để được bind chủ động sau khi vào
console. `ibex_min_top.v` nối AXI của PS vào `ibex_soc` và đưa clock/reset
đến mạch Ibex.

## 3. Trình tự lệnh và phản hồi

```mermaid
sequenceDiagram
    participant User as Console
    participant Cmd as ibex-gpio.c
    participant SCMI as U-Boot SCMI
    participant Mbox as Driver / RTL mailbox
    participant RAM as Shared memory
    participant CPU as Ibex server.c
    participant GPIO as GPIO0 / LED6
    User->>Cmd: pmu_gpio on
    Cmd->>SCMI: Protocol 0x80, message 3, GPIO ID=0, value=1
    SCMI->>RAM: Ghi header + payload, đặt channel busy
    SCMI->>Mbox: Gọi send()
    Mbox->>CPU: Request=1 → machine external IRQ
    CPU->>Mbox: Xóa request
    CPU->>RAM: Đọc và giải mã message
    CPU->>GPIO: Ghi GPIO0=1 → LED sáng
    CPU->>RAM: Ghi response status=0, đặt channel free
    CPU->>Mbox: Completion=1
    SCMI->>Mbox: recv() polling, nhận và xóa completion
    SCMI->>RAM: Đọc response
    SCMI-->>Cmd: Thành công
    Cmd-->>User: Ibex GPIO0: on
```

Phía Ibex chờ ngắt bằng `wfi`; phía U-Boot polling completion để đợi phản hồi.

| Lệnh trên console | Xử lý |
|---|---|
| `ibexinit` | Bind SCMI agent, kiểm tra FCLK1/reset/firmware ready, thực hiện discovery |
| `scmi info` | Xem thông tin SCMI |
| `pmu_gpio on` | Protocol `0x80`, message `3`: SET GPIO0 = 1 |
| `pmu_gpio off` | Protocol `0x80`, message `3`: SET GPIO0 = 0 |
| `pmu_gpio get` | Protocol `0x80`, message `4`: GET giá trị thanh ghi GPIO0 |

Với SET, firmware trả status; U-Boot in giá trị vừa yêu cầu nếu thành công.
Với GET, firmware trả status và giá trị GPIO0. Giá trị GET là trạng thái thanh
ghi điều khiển, không phải đo lại mức điện trên chân LED.

## 4. Khởi động và vai trò FSBL

```mermaid
flowchart TD
    ROM["BootROM"] --> FSBL["FSBL mới"]
    FSBL --> INIT["Khởi tạo PS/DDR/UART<br/>Cấu hình FCLK1 25 MHz"]
    INIT --> PL["Nạp ibex_min.bit<br/>Bật kết nối PS–PL, nhả reset"]
    PL --> CPU["Ibex chạy firmware từ ROM<br/>Khởi tạo GPIO và IRQ, báo ready, chờ WFI"]
    PL --> UB["Chuyển sang U-Boot"]
    UB --> CMD["ibexinit"]
    CMD --> CHECK["ibex-mbox.c kiểm tra<br/>PL configured, FCLK1, reset và firmware ready"]
    CPU --> CHECK
    CHECK --> SCMI["SCMI discovery / sẵn sàng giao tiếp"]
    SCMI --> GPIO["pmu_gpio on/off/get"]
```

FSBL cấu hình clock/reset. Dòng `PL configured; checking FCLK1` trong driver
U-Boot chỉ kiểm tra cấu hình đã có, không cấu hình lại clock và không reset Ibex.

## 5. Các file để đọc code

| File | Vai trò |
|---|---|
| [uboot/ibex-gpio.c](../../../vivado/ibex_min/uboot/ibex-gpio.c) | Đăng ký `ibexinit`, `pmu_gpio`; tạo message và in kết quả |
| [uboot/ibex-mbox.c](../../../vivado/ibex_min/uboot/ibex-mbox.c) | Kiểm tra phần cứng, gửi doorbell, nhận completion |
| [uboot/ibex-scmi.dtsi](../../../vivado/ibex_min/uboot/ibex-scmi.dtsi) | Khai báo SCMI, mailbox, shared memory và clock |
| [uboot/build-client.sh](../../../vivado/ibex_min/uboot/build-client.sh) | Tích hợp phần Ibex và build toàn bộ U-Boot |
| [firmware/server.c](../../../vivado/ibex_min/firmware/server.c) | SCMI server trên Ibex; xử lý IRQ, GPIO và response |
| [firmware/start.S](../../../vivado/ibex_min/firmware/start.S) | Khởi động firmware và thiết lập vector ngắt |
| [firmware/link.ld](../../../vivado/ibex_min/firmware/link.ld) | Bố trí firmware trong bộ nhớ Ibex |
| [rtl/ibex_soc.v](../../../vivado/ibex_min/rtl/ibex_soc.v) | Phần cứng SoC Ibex, mailbox, GPIO và IRQ |
| [rtl/ibex_shared_ram.v](../../../vivado/ibex_min/rtl/ibex_shared_ram.v) | Bộ nhớ trao đổi message giữa PS và Ibex |
| [ibex_min_top.v](../../../vivado/ibex_min/ibex_min_top.v) | Kết nối PS, AXI, clock/reset và SoC Ibex |
| [prepare.ps1](../../../vivado/ibex_min/prepare.ps1) | Build firmware, tạo hex và chuyển RTL Ibex sang Verilog |
| [build.tcl](../../../vivado/ibex_min/build.tcl) | Build phần cứng bằng Vivado |
| [create_fsbl.tcl](../../../vivado/ibex_min/create_fsbl.tcl) | Tạo FSBL từ HDF bằng SDK |
| [boot.bif](../../../vivado/ibex_min/boot.bif) | Danh sách FSBL, bitstream và U-Boot cho Bootgen |
