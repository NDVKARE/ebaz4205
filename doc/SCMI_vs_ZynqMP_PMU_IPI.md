# Phân tích sự khác nhau giữa SCMI Shared Memory và ZynqMP PMU/IPI

## 1. Mục tiêu

Tài liệu này phân tích sự khác nhau giữa:

- **Arm SCMI Shared Memory Transport** theo **DEN0056E – SCMI v3.2**, đặc biệt mục **5.1.2 Shared Memory Area Layout**.
- **PMU Firmware trên Zynq UltraScale+ MPSoC / ZCU102**, sử dụng **IPI (Inter-Processor Interrupt) Message Buffer** và **Xilinx Platform Management API**.
- Cách áp dụng hai kiến trúc này khi xây dựng **PMU Firmware chạy trên Ibex** và giao tiếp với Linux bằng SCMI.

---

## 2. Kết luận ngắn gọn

Điểm quan trọng nhất:

> **SCMI Shared Memory Area và ZynqMP IPI Message Buffer không phải cùng một cơ chế.**

SCMI định nghĩa một giao diện chuẩn cho system management, bao gồm:

- Message header
- Protocol ID
- Message ID
- Token
- Payload
- Shared-memory channel state
- Transport semantics

Trong khi đó ZynqMP PMU Firmware gốc sử dụng:

- Xilinx Platform Management API
- IPI hardware
- IPI request buffer
- IPI response buffer
- IPI interrupt

Hai hệ thống có ý tưởng giống nhau ở mức:

```text
CPU / OS
   |
   | request
   v
message buffer
   |
   | doorbell / interrupt
   v
PM controller
   |
   v
Power / Clock / Reset
```

Nhưng:

- Format message khác nhau.
- Header khác nhau.
- Memory layout khác nhau.
- Transport semantics khác nhau.
- API khác nhau.

---

# 3. Kiến trúc SCMI Shared Memory

SCMI có thể sử dụng shared memory kết hợp với mailbox hoặc doorbell.

Kiến trúc điển hình:

```text
Application Processor / Linux
          |
          | SCMI request
          v
+--------------------------------+
| SCMI Shared Memory Area        |
|                                |
| Channel Status                 |
| Channel Flags                  |
| Length                         |
| Message Header                 |
| Payload                        |
+---------------+----------------+
                |
                | doorbell / mailbox
                v
        SCP / PMU processor
                |
                v
        SCMI dispatcher
                |
       +--------+--------+
       |        |        |
     Power    Clock    Reset
```

Vai trò của shared memory là chứa:

- trạng thái channel;
- metadata;
- message header;
- payload.

Doorbell hoặc mailbox chủ yếu dùng để báo:

> "Có message mới trong shared memory."

---

# 4. SCMI Shared Memory Area Layout

Theo SCMI v3.2, vùng shared memory có layout khái niệm như sau:

| Offset | Field | Chức năng |
|---|---|---|
| `0x00` | Reserved | Reserved |
| `0x04` | Channel Status | Trạng thái channel |
| `0x08` | Reserved | Reserved |
| `0x0C` | Channel Flags | Cờ điều khiển channel |
| `0x10` | Length | Chiều dài message |
| `0x14` | Message Header | SCMI message header |
| `0x18...` | Message Payload | Payload |

SCMI Message Header chứa các trường kiểu:

```text
Message ID
Message Type
Protocol ID
Token
```

Ví dụ khái niệm:

```text
Shared SRAM

+0x00  Reserved
+0x04  Channel Status
+0x08  Reserved
+0x0C  Channel Flags
+0x10  Length
+0x14  SCMI Header
+0x18  Payload
...
```

SCMI transport cần quản lý ownership, status, interrupt và notification của channel.

---

# 5. Kiến trúc PMU Firmware trên Zynq UltraScale+

Zynq UltraScale+ không dùng SCMI Shared Memory Area trong PMU Firmware gốc.

Thay vào đó kiến trúc là:

```text
APU Cortex-A53 / RPU Cortex-R5
              |
              | Xilinx PM API
              v
+--------------------------------+
| IPI Message Buffer             |
|                                |
| Request Buffer                 |
| Response Buffer                |
+---------------+----------------+
                |
                | IPI interrupt
                v
          PMU MicroBlaze
                |
                v
          PMU Firmware
                |
       +--------+--------+
       |        |        |
     Power    Clock    Reset
```

PMU Firmware sử dụng driver IPI để:

```text
ReadMessage()
WriteMessage()
TriggerIpi()
```

Tức là flow cơ bản:

```text
CPU
 |
 | ghi request buffer
 v
IPI message buffer
 |
 | trigger IPI
 v
PMU
 |
 | đọc request
 v
PM API dispatcher
 |
 v
Power / Clock / Reset handler
 |
 | ghi response buffer
 v
CPU
```

---

# 6. IPI Message Buffer trên ZynqMP

ZynqMP có vùng phần cứng dành cho IPI message buffers.

Một base address quan trọng thường được tài liệu ZynqMP mô tả là:

```text
0xFF99_0000
```

Đây là vùng:

```text
IPI Message Buffer Memory
```

Mỗi processor có các vùng request/response tương ứng.

Khái niệm:

```text
IPI Message Buffer Memory
|
+-- APU request buffer
+-- APU response buffer
|
+-- RPU request buffer
+-- RPU response buffer
|
+-- PMU request buffer
+-- PMU response buffer
|
...
```

Các buffer này là **hardware-defined mailbox/message RAM**.

Nó không phải SCMI shared memory.

---

# 7. So sánh trực tiếp

| Hạng mục | SCMI Shared Memory | ZynqMP PMU/IPI |
|---|---|---|
| Chuẩn | Arm SCMI | Xilinx-specific |
| Mục đích | Standard system management interface | ZynqMP platform management |
| Transport | Shared memory + mailbox/doorbell hoặc transport khác | IPI hardware |
| Buffer | Shared memory area | Hardware IPI message buffer |
| Channel Status | Có | Không có field SCMI tương đương |
| Channel Flags | Có | Không có SCMI field tương đương |
| Length | Có field riêng | Thường do API/driver quy ước |
| Header | SCMI Message Header | Xilinx PM API / module encoding |
| Payload | SCMI payload | PM API arguments |
| Notification | Mailbox / doorbell | IPI trigger |
| Response | SCMI response | IPI response buffer |
| PM processor | SCP / platform controller | PMU MicroBlaze |
| Linux support | Linux SCMI framework | Xilinx firmware/driver stack |
| Tính portable | Cao | Thấp hơn, gắn với ZynqMP |

---

# 8. Mapping khái niệm giữa SCMI và ZynqMP

Không thể map byte-by-byte, nhưng có thể map ở mức chức năng:

| SCMI | ZynqMP tương đương gần nhất |
|---|---|
| Shared Memory Area | IPI Message Buffer |
| Channel Status | IPI status + software state |
| Channel Flags | IPI interrupt/control behavior |
| Length | MsgLen / API convention |
| SCMI Message Header | Xilinx PM API / module info |
| Payload | IPI payload words |
| Doorbell | IPI Trigger |
| Response | IPI Response Buffer |
| Platform controller | PMU MicroBlaze |

Điểm giống nhất là:

```text
SCMI doorbell
      ~
ZynqMP IPI Trigger
```

Cả hai đều có vai trò:

> Báo cho phía platform controller rằng có yêu cầu mới.

---

# 9. Tại sao không thể dùng PMUFW ZynqMP như SCMI trực tiếp?

Vì PMUFW ZynqMP không parse SCMI header.

SCMI request có dạng logic:

```text
SCMI Header
|
+-- Protocol ID
+-- Message ID
+-- Message Type
+-- Token
|
+-- Payload
```

Trong khi PMUFW ZynqMP nhận:

```text
Xilinx PM API request
|
+-- module/API information
+-- arguments
```

Ví dụ hai hệ thống cùng có thể yêu cầu:

```text
Power Domain ON
```

nhưng binary message gửi đi khác nhau hoàn toàn.

---

# 10. Phần nào của ZynqMP PMU Firmware nên tham khảo?

Dù không dùng SCMI trực tiếp, PMUFW ZynqMP vẫn là tài liệu tham khảo rất tốt cho PMU Firmware custom.

Nên tham khảo các phần sau.

## 10.1. Event-driven architecture

PMU không polling toàn bộ hệ thống liên tục.

Thay vào đó:

```text
IPI interrupt
    |
    v
PMU handler
    |
    v
dispatch request
```

Đây là mô hình phù hợp cho Ibex PMU.

---

## 10.2. Transport tách khỏi PM logic

Kiến trúc nên tách:

```text
Transport
   |
Dispatcher
   |
Protocol handlers
   |
Platform HAL
```

Không nên viết kiểu:

```text
SPI interrupt
  -> trực tiếp power off domain
```

Nên có abstraction layer.

---

## 10.3. Request dispatcher

Ví dụ:

```text
Incoming Request
      |
      v
+----------------+
| Dispatcher     |
+----------------+
      |
      +--> Power handler
      |
      +--> Clock handler
      |
      +--> Reset handler
      |
      +--> Sensor handler
```

SCMI cũng dùng tư duy tương tự.

---

## 10.4. Resource management

PMUFW ZynqMP có thể tham khảo cách:

- power up/down;
- reset;
- wakeup;
- clock;
- error handling;
- event handling;
- dependency giữa domain.

---

# 11. Kiến trúc đề xuất cho Ibex PMU + SCMI

Nếu mục tiêu là:

```text
Linux
  |
SCMI
  |
Ibex PMU Firmware
```

thì kiến trúc nên là:

```text
Linux SCMI Core
      |
      | SCMI request
      v
+----------------------------------+
| SCMI Shared Memory Area          |
|                                  |
| Channel Status                   |
| Channel Flags                    |
| Length                           |
| SCMI Header                      |
| Payload                          |
+----------------+-----------------+
                 |
                 | mailbox / IPI
                 v
             Ibex PMU
                 |
        +--------+--------+
        | SCMI transport  |
        +--------+--------+
                 |
        +--------+--------+
        | SCMI dispatcher |
        +--------+--------+
                 |
       +---------+----------+
       |         |          |
     Power     Clock      Reset
       |         |          |
       +---------+----------+
                 |
          SoC registers
```

---

# 12. Firmware layer đề xuất

Có thể chia firmware Ibex thành:

```text
+-----------------------------------+
| SCMI Protocol Handlers            |
| Base / Power / Clock / Reset      |
+-----------------------------------+
| SCMI Dispatcher                   |
+-----------------------------------+
| SCMI Transport Layer              |
+-----------------------------------+
| Mailbox / Shared RAM / SPI HAL    |
+-----------------------------------+
| Platform HAL                      |
| Power / Reset / Clock Registers   |
+-----------------------------------+
| Hardware                          |
+-----------------------------------+
```

Chi tiết:

| Layer | Chức năng |
|---|---|
| Transport HAL | Shared RAM, mailbox, SPI, IRQ |
| SCMI Transport | Channel state, flags, length |
| SCMI Dispatcher | Decode Protocol ID + Message ID |
| Protocol Handler | Power / Clock / Reset |
| Platform HAL | Ghi register SoC |
| Diagnostics | Log, error, timeout |

---

# 13. Nếu Linux ↔ Ibex dùng SPI

SCMI bản thân là protocol.

Transport có thể custom.

Ví dụ:

```text
Linux
  |
SCMI Core
  |
Custom SCMI SPI transport
  |
SPI Controller
  |
==============================
SPI physical connection
==============================
  |
SPI Slave RTL
  |
FIFO
  |
Ibex
  |
SCMI Dispatcher
```

Khi đó không nhất thiết phải có:

```text
Shared SRAM vật lý
```

Nhưng custom transport phải tự định nghĩa:

- framing;
- message length;
- ownership;
- request/response;
- timeout;
- notification;
- error handling.

Ví dụ frame:

```text
+---------+---------+-------------+
| Length  | Header  | Payload     |
+---------+---------+-------------+
```

Trong đó:

```text
Header/Payload = SCMI message
```

---

# 14. Khuyến nghị cho giai đoạn bring-up

Để phát triển Ibex PMU dễ debug:

## Giai đoạn 1

Chạy Ibex trước:

```text
Ibex
 |
UART
 |
Hello PMU
```

## Giai đoạn 2

Tạo transport đơn giản:

```text
Linux
 |
Shared RAM / SPI
 |
Ibex
```

Test raw request/response.

## Giai đoạn 3

Implement SCMI Base Protocol:

```text
PROTOCOL_VERSION
PROTOCOL_ATTRIBUTES
PROTOCOL_MESSAGE_ATTRIBUTES
DISCOVER_VENDOR
DISCOVER_SUB_VENDOR
DISCOVER_IMPLEMENTATION_VERSION
```

## Giai đoạn 4

Thêm:

```text
Power Domain Protocol
Clock Protocol
Reset Domain Protocol
```

## Giai đoạn 5

Thêm:

```text
Sensor
Performance
DVFS
Notifications
```

---

# 15. Tư duy thiết kế nên dùng

Không nên thiết kế:

```text
Linux
 |
Xilinx PM API
 |
Ibex
```

nếu mục tiêu cuối cùng là SCMI.

Nên thiết kế:

```text
Linux SCMI
 |
SCMI Transport
 |
Ibex SCMI Server
 |
Platform HAL
```

Còn ZynqMP PMUFW chỉ dùng như:

```text
reference architecture
```

cho:

- PM controller design;
- interrupt flow;
- request dispatch;
- power state machine;
- reset management;
- clock management;
- error handling.

---

# 16. Kết luận

SCMI Shared Memory và ZynqMP IPI Message Buffer giống nhau ở mô hình tổng quát:

```text
CPU
 |
message
 |
shared buffer
 |
doorbell
 |
PM controller
```

nhưng khác nhau ở implementation.

SCMI:

```text
Standard protocol
+
Standard message format
+
Defined shared memory layout
```

ZynqMP PMUFW:

```text
Xilinx PM API
+
IPI hardware
+
Xilinx-specific message buffers
```

Do đó với Ibex PMU:

> **Dùng SCMI specification làm chuẩn cho protocol.**

> **Dùng ZynqMP PMU Firmware làm reference cho cách tổ chức PM controller firmware.**

Kiến trúc phù hợp:

```text
Linux SCMI
     |
     v
SCMI transport
     |
     v
Ibex SCMI server
     |
     v
Power / Clock / Reset HAL
     |
     v
SoC hardware
```

---

# 17. Tài liệu tham khảo

1. **Arm DEN0056E – System Control and Management Interface Specification v3.2**
   - Đặc biệt mục `5.1.2 Shared Memory Area Layout`.

2. **AMD/Xilinx UG1085 – Zynq UltraScale+ Device Technical Reference Manual**
   - IPI Interrupts
   - IPI Message Buffers
   - Platform Management Unit

3. **AMD/Xilinx UG1137 – Zynq UltraScale+ MPSoC Software Developers Guide**
   - PMU Firmware
   - IPI Manager
   - Platform Management

4. **Xilinx embeddedsw**
   - `zynqmp_pmufw`
   - `xpfw_ipi_manager.c`
   - `xpfw_core.c`
   - PM API handlers

5. **Arm SCP-firmware**
   - SCMI server implementation
   - transport layer
   - protocol handlers
