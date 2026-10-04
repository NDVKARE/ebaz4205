# Lệnh mặc định khi nhấn phím ↑ trong U-Boot

U-Boot nạp sẵn mười lệnh vào command history sau mỗi lần khởi động:

```text
ibexinit
scmi info
pmu_gpio 0 on
pmu_gpio 0 off
pmu_clock rate
pmu_clock set 10
pmu_clock on
pmu_clock off
nand info
jtag_sd_update
```

Ở dấu nhắc `Zynq>`, nhấn phím ↑ một lần sẽ hiện `jtag_sd_update`; tiếp tục nhấn
↑ sẽ lùi lần lượt qua danh sách. Lệnh chỉ được đưa lên dòng nhập, chưa chạy cho
đến khi nhấn Enter. Phím ↓ đi theo chiều ngược lại.

Các lệnh nhập sau đó vẫn được thêm vào history như bình thường. History chứa
tối đa 20 dòng; các lệnh mới sẽ dần thay thế lệnh cũ. Khi reset, danh sách trên
được nạp lại từ đầu.

`saveenv` không tham gia cơ chế này. Nó chỉ lưu biến môi trường U-Boot; command
history vẫn nằm trong RAM và được khởi tạo lại khi boot.

Phần sửa được lưu dưới dạng
[cli-default-history.patch](../../../vivado/ibex_min/uboot/cli-default-history.patch)
và được [build-client.sh](../../../vivado/ibex_min/uboot/build-client.sh) áp dụng
tự động vào `common/cli_readline.c` trước khi build U-Boot.

## Kết quả build

- U-Boot build thành công, bao gồm `common/cli_readline.o` đã sửa.
- Toàn bộ mười lệnh và thông báo khởi tạo history có trong ảnh đóng gói.
- Ba checksum partition header đều hợp lệ.
- Ảnh trước thay đổi được lưu tại
  `vivado/ibex_min/recovery_before_default_history/BOOT-GPIO.BIN`.

Ảnh hiện tại: [BOOT-GPIO.BIN](../../../vivado/ibex_min/BOOT-GPIO.BIN),
`3.171.120` byte. SHA256:
`A97ED22D893B41CD4711DDF95E25CF3ABCFDAFE9F8F795B1FD92E8098DB5B624`.

Chưa kiểm tra thao tác phím ↑ trên bo vật lý.
