# Phân tích log SCMI theo thứ tự gửi

Tài liệu phân tích đoạn log người dùng cung cấp, giữ đúng thứ tự 10 giao
dịch: 9 giao dịch discovery Base protocol, sau đó 1 giao dịch GPIO_SET.
Log bắt đầu khi trao đổi SCMI đã diễn ra; không có phần boot/kiểm tra clock.

## Cách đọc một giao dịch

Các dòng TX/RX là snapshot và các lần ghi mailbox của driver, không phải
trace từng giao dịch AXI. Thứ tự log trong mỗi giao dịch là:

1. **TX channel_status = 0:** U-Boot đã đánh dấu channel đang bận.
2. **TX flags = 1:** giá trị flags thực tế trong shared memory. Firmware
   hiện không dùng flags để phát ngắt về PS; PS vẫn polling completion.
3. **TX length:** số byte header + payload, không tính metadata SMT.
4. **TX header:** định danh protocol, message, type và token.
5. **TX payload nếu có:** tham số của yêu cầu.
6. **TX completion = 0:** U-Boot xóa completion của giao dịch trước.
7. **TX request = 1:** U-Boot báo yêu cầu mới; RTL kích ngắt Ibex.
8. **RX completion = 1:** driver nhận thấy firmware xử lý xong.
9. **RX channel_status = 1:** firmware đã trả channel về trạng thái rảnh.
10. **RX flags/length/header/payload:** driver đọc response trong shared memory.
11. **RX gpio_bitmap:** đọc thanh ghi trạng thái điều khiển 5 GPIO.
12. **RX completion ACK = 0:** U-Boot xác nhận và xóa completion.

Firmware còn xóa request về 0 trong ISR, nhưng thao tác đó không được
driver U-Boot ghi log riêng.

| Địa chỉ PS | Nội dung |
|---|---|
| `0x43C01004` | Channel status |
| `0x43C01010` | Flags |
| `0x43C01014` | Length |
| `0x43C01018` | Header |
| `0x43C0101C` trở đi | Payload; response luôn bắt đầu bằng status |
| `0x43C00000` | Request doorbell |
| `0x43C00004` | Completion doorbell |
| `0x43C00010` | GPIO bitmap: bit 0=LED6; bit 1..4=DATA1 chân 5..8 |

Header trong bản này được giải mã như sau:

```text
message ID  = header & 0xFF
message type = (header >> 8) & 0x3
protocol ID = (header >> 10) & 0xFF
token       = (header >> 18) & 0x3FF
```

Mọi header trong log có type=0 và token=0. Firmware giữ nguyên header khi
trả lời theo cách triển khai hiện tại; completion/channel status xác định
thời điểm response sẵn sàng.

## 1. Hỏi phiên bản Base protocol — lần thứ nhất

**TX:**

```text
length = 0x04
header = 0x00004000
```

- Protocol = `0x10`: Base protocol.
- Message ID = `0`: PROTOCOL_VERSION.
- Không có payload; length chỉ gồm header 4 byte.
- U-Boot xóa completion rồi ghi request=1.

**RX:**

```text
length              = 0x0C
[0x43C0101C] status  = 0x00000000
[0x43C01020] version = 0x00020000
gpio_bitmap         = 0x00000000
```

Status=0 nghĩa là thành công. Version `0x00020000` là major=2, minor=0:
Base protocol phiên bản **2.0**. Response dài 12 byte: header + status +
version. GPIO chưa thay đổi.

## 2. Hỏi phiên bản Base protocol — lần thứ hai

TX/RX giống giao dịch 1:

```text
TX header = 0x00004000; length = 0x04
RX status = 0; version = 0x00020000; length = 0x0C
```

U-Boot gửi lại cùng yêu cầu và Ibex trả thành công. Log này không đủ để
xác định chính xác call site gây lần hỏi lặp; nó không thể hiện retry do lỗi.
GPIO bitmap vẫn bằng 0.

## 3. Hỏi khả năng của Base protocol

**TX:** `header=0x00004001`, `length=0x04`.

- Protocol `0x10`, message `1`: PROTOCOL_ATTRIBUTES.
- Không có tham số.

**RX:**

```text
[0x43C0101C] status     = 0x00000000
[0x43C01020] attributes = 0x00000201
length                 = 0x0C
```

Theo firmware hiện tại, attributes được tạo bằng `(2 << 8) | 1`:

- Có **2 agent**: platform và PS/U-Boot.
- Có **1 protocol ngoài Base**, sẽ được hỏi cụ thể ở giao dịch 9.

## 4. Hỏi tên vendor

**TX:** `header=0x00004003`, `length=0x04`.

- Protocol `0x10`, message `3`: BASE_DISCOVER_VENDOR.

**RX:**

```text
[0x43C0101C] status = 0x00000000
[0x43C01020]        = 0x5A414245
[0x43C01024]        = 0x35303234
[0x43C01028]        = 0x00000000
[0x43C0102C]        = 0x00000000
length             = 0x18
```

Chuỗi dùng thứ tự byte little-endian:

```text
0x5A414245 → 45 42 41 5A → E B A Z
0x35303234 → 34 32 30 35 → 4 2 0 5
```

Tên vendor là **EBAZ4205**. Response dài 24 byte: header 4 + status 4 +
trường tên 16 byte, có byte 0 đệm ở cuối.

## 5. Hỏi tên sub-vendor

**TX:** `header=0x00004004`, `length=0x04`.

- Protocol `0x10`, message `4`: BASE_DISCOVER_SUB_VENDOR.

**RX:**

```text
[0x43C0101C] status = 0x00000000
[0x43C01020]        = 0x78656249
[0x43C01024..2C]    = 0
length             = 0x18
```

`0x78656249` có byte `49 62 65 78`, tức **Ibex**. Đây là thông tin
nhận diện do firmware trả về, không phải thao tác GPIO.

## 6. Hỏi implementation version

**TX:** `header=0x00004005`, `length=0x04`.

- Protocol `0x10`, message `5`: BASE_DISCOVER_IMPLEMENTATION_VERSION.

**RX:**

```text
[0x43C0101C] status  = 0x00000000
[0x43C01020] version = 0x00000001
length              = 0x0C
```

Implementation version bằng **1**, do firmware tự quy định. Nó khác với
Base protocol version 2.0 ở giao dịch 1 và 2.

## 7. Hỏi danh tính agent đang gọi

**TX:**

```text
header                 = 0x00004007
length                 = 0x08
[0x43C0101C] agent ID  = 0xFFFFFFFF
```

- Protocol `0x10`, message `7`: BASE_DISCOVER_AGENT.
- `0xFFFFFFFF` là ID đặc biệt: hỏi agent đang gọi yêu cầu này.
- Length=8: header 4 byte + agent ID 4 byte.

**RX:**

```text
[0x43C0101C] status   = 0x00000000
[0x43C01020] agent ID = 0x00000001
[0x43C01024]          = 0x6F422D55
[0x43C01028]          = 0x0000746F
[0x43C0102C]          = 0x00000000
[0x43C01030]          = 0x00000000
length               = 0x1C
```

Giải mã little-endian:

```text
0x6F422D55 → U - B o
0x0000746F → o t 0 0
```

Agent đang gọi là **ID 1, tên U-Boot**. Response dài 28 byte:
header 4 + status 4 + agent ID 4 + tên 16.

## 8. Hỏi lại Base attributes

**TX:** `header=0x00004001`, `length=0x04`.

**RX:** status=0, attributes=`0x00000201`, length=`0x0C`.

Kết quả giống giao dịch 3: 2 agent và 1 protocol bổ sung. Lần hỏi lặp
thành công; log không chỉ ra call site cụ thể. GPIO bitmap vẫn bằng 0.

## 9. Hỏi danh sách protocol ngoài Base

**TX:**

```text
header                  = 0x00004006
length                  = 0x08
[0x43C0101C] skip count = 0x00000000
```

- Protocol `0x10`, message `6`: BASE_DISCOVER_LIST_PROTOCOLS.
- Skip=0: lấy danh sách từ đầu.

**RX:**

```text
[0x43C0101C] status   = 0x00000000
[0x43C01020] count    = 0x00000001
[0x43C01024] protocol = 0x00000080
length               = 0x10
```

Ibex báo có **1 protocol bổ sung, ID 0x80**. Đây là GPIO protocol riêng
của dự án, không phải GPIO protocol chuẩn của SCMI.
Response dài 16 byte: header + status + count + word chứa protocol ID.
Đến đây, toàn bộ 9 giao dịch discovery đều thành công và GPIO bitmap
vẫn bằng 0.

## 10. Gửi GPIO_SET để bật GPIO0

Log chuyển sang lệnh người dùng:

```text
PMU GPIO SCMI: protocol=0x80 message=0x03 gpio=0 action=on
```

### 10.1. U-Boot chuẩn bị request

```text
SCMI TX channel_status [0x43C01004] = 0x00000000
SCMI TX flags          [0x43C01010] = 0x00000001
SCMI TX length         [0x43C01014] = 0x0000000C
SCMI TX header         [0x43C01018] = 0x00020003
SCMI TX payload        [0x43C0101C] = 0x00000000
SCMI TX payload        [0x43C01020] = 0x00000001
```

Header `0x00020003` gồm protocol `0x80` dịch trái 10 bit và message ID=3.
Hai word payload là:

1. **GPIO ID=0**: chọn LED6 xanh.
2. **Value=1**: bật.

Length=12 byte: header 4 + GPIO ID 4 + value 4.
Đây là nội dung yêu cầu SCMI; U-Boot chưa trực tiếp ghi thanh ghi GPIO.

### 10.2. U-Boot báo yêu cầu cho Ibex

```text
SCMI TX completion [0x43C00004] = 0x00000000
SCMI TX request    [0x43C00000] = 0x00000001
```

Driver xóa completion cũ, rồi ghi request=1. RTL phát ngắt machine
external cho Ibex. Firmware đọc yêu cầu và đổi bit 0 của thanh ghi GPIO:

```c
REG(0x10) = (REG(0x10) & ~(1u << 0)) | (1u << 0);
```

Địa chỉ firmware nhìn thấy là `0x30000010`; PS nhìn cùng thanh ghi tại
`0x43C00010`. Trước lệnh bitmap=0, sau lệnh bitmap=1.
RTL đảo bit 0 để điều khiển chân LED6 active-low.

### 10.3. Ibex trả response

```text
SCMI RX completion     [0x43C00004] = 0x00000001
SCMI RX channel_status [0x43C01004] = 0x00000001
SCMI RX flags          [0x43C01010] = 0x00000001
SCMI RX length         [0x43C01014] = 0x00000008
SCMI RX header         [0x43C01018] = 0x00020003
SCMI RX payload        [0x43C0101C] = 0x00000000
SCMI RX gpio_bitmap    [0x43C00010] = 0x00000001
```

- Completion=1: firmware xử lý xong.
- Channel status=1: channel đã rảnh.
- Header khớp yêu cầu.
- Status=0: GPIO_SET thành công.
- Length=8: header + status. SET không trả word giá trị GPIO riêng.
- Bitmap=`0b00001`: GPIO0 bật, GPIO1..4 tắt.

### 10.4. U-Boot xác nhận completion và in kết quả

```text
SCMI RX completion ACK [0x43C00004] = 0x00000000
PMU GPIO0: on
```

U-Boot xóa completion để chuẩn bị giao dịch tiếp theo. Dòng `PMU GPIO0: on`
được in sau khi transport và firmware status đều báo thành công.
Đối với SET, dòng này dùng giá trị yêu cầu; dòng bitmap phía trên xác nhận
thêm rằng thanh ghi điều khiển thực sự đã có bit 0 bằng 1.

## Kết quả và giới hạn của đoạn log

- Cả 10 giao dịch đều có response status=0; không thấy timeout/lỗi transport.
- Base discovery nhận diện đúng firmware Ibex và protocol GPIO 0x80.
- Lệnh cuối bật GPIO0; bitmap chuyển từ 0 sang 1.
- Log chứng minh trạng thái thanh ghi điều khiển, không đo mức điện trên chân.
- Đoạn này chưa có GPIO_GET và chưa kiểm tra GPIO1..4 trên DATA1.
- Dòng `gpio=0` phù hợp với `pmu_gpio on` hoặc `pmu_gpio 0 on`;
  log không chứa dòng nhập lệnh nên không phân biệt được hai cách gõ.

Để kiểm tra DATA1 chân 5 trong khi GPIO0 đang bật:

```text
pmu_gpio 1 on
pmu_gpio 1 get
pmu_gpio 1 off
```

Bitmap mong đợi lần lượt là `0x03`, `0x03`, `0x01`, nếu không có lệnh nào
khác đổi GPIO. Với GET, status tại `0x43C0101C` bằng 0 và giá trị trả về
tại `0x43C01020` bằng 1 sau khi bật.

## Code liên quan

- [uboot/ibex-gpio.c](../../../vivado/ibex_min/uboot/ibex-gpio.c): tạo message GPIO và in kết quả.
- [uboot/ibex-mbox.c](../../../vivado/ibex_min/uboot/ibex-mbox.c): in snapshot TX/RX, gửi request và ACK completion.
- [firmware/server.c](../../../vivado/ibex_min/firmware/server.c): xử lý discovery, GPIO_SET/GET và response.
- [rtl/ibex_soc.v](../../../vivado/ibex_min/rtl/ibex_soc.v): mailbox, IRQ và thanh ghi GPIO.
- [GPIO_DATA1.md](GPIO_DATA1.md): ánh xạ chân và sơ đồ nhiều GPIO.
