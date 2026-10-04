param(
    [string]$OutputPath = (Join-Path $PSScriptRoot "..\doc\vivado\ibex_min\Bao_cao_tich_hop_Ibex_SCMI_EBAZ4205.doc")
)

$ErrorActionPreference = 'Stop'

function RtfEscape([string]$Text) {
    $builder = [System.Text.StringBuilder]::new()
    foreach ($ch in $Text.ToCharArray()) {
        $code = [int][char]$ch
        switch ($ch) {
            '\' { [void]$builder.Append('\\') }
            '{'  { [void]$builder.Append('\{') }
            '}'  { [void]$builder.Append('\}') }
            default {
                if ($code -gt 127) {
                    if ($code -gt 32767) { $code -= 65536 }
                    [void]$builder.Append("\u${code}?")
                } else {
                    [void]$builder.Append($ch)
                }
            }
        }
    }
    $builder.ToString()
}

$rtf = [System.Text.StringBuilder]::new()
function Add-Raw([string]$Text) { [void]$script:rtf.Append($Text) }
function Add-P([string]$Text, [string]$Style = '') {
    Add-Raw "\pard$Style "
    Add-Raw (RtfEscape $Text)
    Add-Raw "\par`n"
}
function Add-H1([string]$Text) { Add-P $Text '\sb240\sa120\keepn\b\fs32\cf1' }
function Add-H2([string]$Text) { Add-P $Text '\sb180\sa80\keepn\b\fs27\cf2' }
function Add-H3([string]$Text) { Add-P $Text '\sb120\sa60\keepn\b\fs24' }
function Add-Bullet([string]$Text) { Add-P ("• " + $Text) '\li540\fi-300\sa45' }
function Add-Code([string]$Text) { Add-P $Text '\li360\ri180\sb40\sa40\f1\fs19\highlight1' }
function Add-PageBreak { Add-Raw "\page`n" }

Add-Raw '{\rtf1\ansi\ansicpg1252\deff0\uc1'
Add-Raw '{\fonttbl{\f0 Calibri;}{\f1 Consolas;}{\f2 Cambria;}}'
Add-Raw '{\colortbl;\red31\green78\blue121;\red46\green116\blue181;\red242\green242\blue242;\red89\green89\blue89;}'
Add-Raw '\paperw11907\paperh16840\margl1134\margr1134\margt1134\margb1134\widowctrl\viewkind4\fs22'
Add-Raw '{\footer\pard\qc\fs18\cf4 EBAZ4205 - Ibex/SCMI\tab Trang {\field{\*\fldinst PAGE}{\fldrslt 1}}\par}'

Add-P 'BÁO CÁO TÍCH HỢP IBEX FIRMWARE VÀ SCMI TRÊN EBAZ4205' '\qc\sb1800\sa240\b\fs42\cf1\f2'
Add-P 'Thiết kế RTL, firmware RISC-V, FSBL, U-Boot và cơ chế điều khiển từ dòng lệnh' '\qc\sa600\fs26\cf2'
Add-P 'Dự án: EBAZ4205-PetaLinux / ibex_min' '\qc\sa100\b\fs24'
Add-P 'Ngày lập tài liệu: 04/10/2026' '\qc\sa100\fs22'
Add-P 'Trạng thái: Đã xây dựng và tích hợp; cần xác nhận toàn bộ chức năng trên bo mục tiêu' '\qc\sa900\i\fs20'
Add-P 'Phạm vi ảnh boot hiện tại' '\qc\b\fs22\cf1'
Add-P 'BOOT.BIN = FSBL tùy biến + bitstream ibex_min + U-Boot tùy biến' '\qc\fs21'
Add-P 'image.ub và boot.scr của PetaLinux được giữ nguyên trong lần cập nhật U-Boot này.' '\qc\fs20'
Add-PageBreak

Add-H1 '1. Mục tiêu và kết quả đạt được'
Add-P 'Hệ thống đã tích hợp một lõi Ibex RISC-V trong phần PL của Zynq-7000. Firmware do dự án tự xây dựng chạy trực tiếp trên Ibex và cung cấp dịch vụ SCMI cho U-Boot chạy trên Cortex-A9 phía PS. U-Boot có thể gửi lệnh, chờ Ibex xử lý, nhận mã trạng thái cùng dữ liệu trả về và hiển thị kết quả trên UART.'
Add-Bullet 'Xây dựng firmware Ibex độc lập, được nhúng vào ROM BRAM của bitstream.'
Add-Bullet 'Cài đặt SCMI Base 2.0, SCMI Clock 1.0 và giao thức GPIO riêng ID 0x80.'
Add-Bullet 'Tạo mailbox, shared memory và ngắt PS → Ibex trong RTL.'
Add-Bullet 'Tạo driver mailbox và các lệnh điều khiển trong U-Boot.'
Add-Bullet 'Build lại FSBL và U-Boot theo phần cứng ibex_min; đóng gói cùng bitstream thành BOOT.BIN.'
Add-Bullet 'Cấp FCLK1 25 MHz từ giai đoạn khởi động để Ibex, AXI và mailbox hoạt động trước khi U-Boot kết nối SCMI.'
Add-Bullet 'Cho phép điều khiển GPIO, điều khiển clock LED và đọc lại trạng thái từ U-Boot.'
Add-Bullet 'Bổ sung S2 reset trong U-Boot và cơ chế chỉ cập nhật BOOT.BIN trên thẻ SD qua JTAG.'

Add-H2 '1.1. Sản phẩm đầu ra chính'
Add-P 'Ảnh boot mới được tạo tại E:\EBAZ4205-build\BOOT.BIN. Ảnh đóng gói tương ứng trong cây dự án là vivado\ibex_min\BOOT-PETALINUX-IBEX.BIN. BOOT.BIN có kích thước 3.170.808 byte và SHA-256 B9575D3EC8BF5796107DEDB732699A87FCF6280600A24C3E7C17714E8201FDBB tại thời điểm lập tài liệu.'

Add-H1 '2. Kiến trúc hệ thống'
Add-Code 'U-Boot / Cortex-A9 (PS)'
Add-Code '  Lệnh ibexinit, pmu_gpio, pmu_clock'
Add-Code '       |  SCMI framework + driver ibex_mbox'
Add-Code '       |  AXI GP0, địa chỉ 0x43C00000'
Add-Code '       v'
Add-Code 'Mailbox registers + Shared BRAM (PL)'
Add-Code '       | request tạo IRQ             ^ completion / response'
Add-Code '       v                             |'
Add-Code 'Ibex RISC-V + firmware SCMI ------ GPIO / clock LED'
Add-P 'AXI là đường truy cập phần cứng từ PS sang PL. Mailbox cung cấp tín hiệu yêu cầu và hoàn tất. Shared BRAM chứa header cùng payload SCMI. Firmware Ibex sở hữu các ngõ ra; U-Boot không ghi trực tiếp GPIO mà gửi yêu cầu qua SCMI.'

Add-H2 '2.1. Clock và reset'
Add-Bullet 'FCLK0 của PS: 100 MHz.'
Add-Bullet 'FCLK1 của PS: 25 MHz, cấp cho lõi Ibex, AXI bridge, mailbox và reset synchronizer.'
Add-Bullet 'Device tree U-Boot tham chiếu PS FCLK1 qua clock ID 16.'
Add-Bullet 'Driver mailbox kiểm tra PL đã được cấu hình, reset đã nhả và tần số FCLK1 nằm trong khoảng 24,9–25,1 MHz.'
Add-Bullet 'Firmware đã chạy từ khi bitstream được FSBL nạp. U-Boot chỉ kết nối với firmware đang chạy, không nạp lại firmware và không reset Ibex.'

Add-H2 '2.2. Bản đồ địa chỉ phía PS'
Add-Code '0x43C00000  request/doorbell'
Add-Code '0x43C00004  completion'
Add-Code '0x43C00008  ready signature = 0x49424558 ("IBEX")'
Add-Code '0x43C00010  bitmap trạng thái GPIO'
Add-Code '0x43C00014  trap cause do firmware lưu'
Add-Code '0x43C00018  CPU fault (chỉ đọc từ PS)'
Add-Code '0x43C0001C  bộ đếm ngắt đã xử lý'
Add-Code '0x43C00020  trạng thái Ibex đang ngủ/chờ'
Add-Code '0x43C00024  clock LED enable'
Add-Code '0x43C00028  tần số clock LED, đơn vị Hz'
Add-Code '0x43C01000..0x43C01FFF  shared memory SCMI, 4 KiB'

Add-H2 '2.3. Bản đồ bộ nhớ phía Ibex'
Add-Code '0x00000000  ROM firmware, 16 KiB'
Add-Code '0x10000000  RAM dữ liệu và stack, 8 KiB'
Add-Code '0x20000000  shared memory SCMI, 4 KiB'
Add-Code '0x30000000  các thanh ghi mailbox/GPIO/chẩn đoán'
Add-P 'Vùng 0x43C01000 phía PS và 0x20000000 phía Ibex là cùng một BRAM hai cổng. Dữ liệu SCMI không cần copy qua DDR.'

Add-H1 '3. Firmware Ibex tự xây dựng'
Add-P 'Firmware được viết theo mô hình bare-metal, không phụ thuộc hệ điều hành. Mã khởi động thiết lập vector, stack và vùng dữ liệu; vòng lặp chính đưa CPU về trạng thái chờ WFI. Khi U-Boot ghi request, RTL phát ngắt mức tới Ibex. ISR xóa request, tăng bộ đếm ngắt, xử lý bản tin trong shared memory, ghi phản hồi, giải phóng kênh và đặt completion.'

Add-H2 '3.1. Các dịch vụ SCMI'
Add-Bullet 'Base protocol 0x10, phiên bản 2.0: discovery vendor, implementation, agent và danh sách protocol.'
Add-Bullet 'Clock protocol 0x14, phiên bản 1.0: attributes, describe rates, rate set/get và config set.'
Add-Bullet 'GPIO vendor protocol 0x80, phiên bản 1.0: GPIO_SET ID 3 và GPIO_GET ID 4.'
Add-Bullet 'Mã kết quả: SUCCESS=0, NOT_SUPPORTED=-1, INVALID_PARAMETERS=-2, NOT_FOUND=-3.'

Add-H2 '3.2. GPIO được điều khiển'
Add-Bullet 'GPIO0: LED6 xanh.'
Add-Bullet 'GPIO1 đến GPIO4: DATA1 chân 5 đến chân 8.'
Add-P 'Firmware lưu trạng thái các GPIO thành bitmap để U-Boot có thể đọc lại. GPIO ID ngoài 0..4 hoặc giá trị SET không hợp lệ bị từ chối.'

Add-H2 '3.3. Clock LED6 đỏ'
Add-P 'Clock ID 0 điều khiển LED6 đỏ. Tần số cho phép từ 1 đến 100 Hz; mặc định sau reset là 1 Hz và clock đang tắt. RATE_SET không tự bật clock. CONFIG_SET bật hoặc tắt mà vẫn giữ lại tần số đã cấu hình. RTL dùng bộ tích lũy pha theo nguồn 25 MHz để tạo tần số trung bình chính xác, kể cả khi 25.000.000 không chia hết cho tần số yêu cầu.'

Add-H2 '3.4. Định dạng shared memory'
Add-Code 'offset 0x04: channel_status; bit 0 = 1 nghĩa là kênh rảnh'
Add-Code 'offset 0x10: flags'
Add-Code 'offset 0x14: length của header + payload'
Add-Code 'offset 0x18: SCMI message header'
Add-Code 'offset 0x1C: payload bắt đầu'
Add-P 'Header 32 bit gồm message ID [7:0], message type [9:8], protocol ID [17:10] và token [27:18]. Firmware giữ nguyên token trong phản hồi để client ghép đúng giao dịch.'

Add-H1 '4. Tích hợp FSBL, bitstream và U-Boot'
Add-H2 '4.1. FSBL theo RTL'
Add-P 'FSBL được build từ hardware description của thiết kế ibex_min. Vai trò của FSBL là khởi tạo PS, DDR, UART và clock, nạp bitstream PL, sau đó chuyển điều khiển sang U-Boot. Nhờ FCLK1 25 MHz và reset PL được chuẩn bị từ đầu, firmware trong ROM BRAM có thể chạy trước lúc U-Boot tạo SCMI agent.'

Add-H2 '4.2. Device tree và driver U-Boot'
Add-P 'Device tree khai báo mailbox tại 0x43C00000, shared SRAM tại 0x43C01000 và reset S2 tại MIO20. Node /firmware/scmi được để disabled nhằm tránh discovery quá sớm khi console chưa sẵn sàng. Lệnh ibexinit bind node theo yêu cầu sau khi U-Boot đã lên UART.'
Add-P 'Driver ibex_mbox kiểm tra điều kiện phần cứng, đợi ready signature, ghi request và polling completion. Driver ghi log payload TX/RX, bitmap GPIO và trạng thái clock để hỗ trợ chẩn đoán. U-Boot SCMI framework đảm nhiệm đóng gói header, chiều dài, token và sao chép payload.'

Add-H2 '4.3. Thành phần BOOT.BIN'
Add-Code 'FSBL:     vivado\ibex_min\fsbl_new\executable.elf'
Add-Code 'Bitstream: vivado\ibex_min\ibex_min.bit'
Add-Code 'U-Boot:   vivado\ibex_min\uboot\u-boot-ibex.elf'
Add-P 'Lệnh boot mặc định của U-Boot gọi ibexinit, đọc image.ub từ phân vùng FAT đầu tiên của thẻ SD vào địa chỉ 0x03000000 rồi bootm. Thời gian chờ autoboot là 3 giây.'
Add-Code 'ibexinit; fatload mmc 0:1 0x03000000 image.ub; bootm 0x03000000'

Add-H1 '5. Các lệnh U-Boot đã bổ sung'
Add-H2 '5.1. Khởi tạo SCMI'
Add-Code 'ibexinit'
Add-P 'Kết quả mong đợi: U-Boot bind SCMI sau khi console hoạt động, driver nhận ready signature và in “Ibex SCMI ready”. Các lệnh pmu_gpio và pmu_clock cũng tự gọi bước khởi tạo nếu người dùng chưa chạy ibexinit.'

Add-H2 '5.2. Điều khiển và đọc GPIO'
Add-Code 'pmu_gpio on'
Add-Code 'pmu_gpio off'
Add-Code 'pmu_gpio get'
Add-Code 'pmu_gpio 0 on'
Add-Code 'pmu_gpio 1 on'
Add-Code 'pmu_gpio 4 get'
Add-P 'Cú pháp không có ID mặc định dùng GPIO0. Cú pháp có ID hỗ trợ GPIO0..4. Sau giao dịch thành công, U-Boot in trạng thái “PMU GPIOx: on/off”. Lệnh get nhận giá trị thực tế do firmware trả về.'

Add-H2 '5.3. Điều khiển clock LED6 đỏ'
Add-Code 'pmu_clock set 10'
Add-Code 'pmu_clock rate'
Add-Code 'pmu_clock on'
Add-Code 'pmu_clock get'
Add-Code 'pmu_clock set 100'
Add-Code 'pmu_clock off'
Add-P 'set chỉ chấp nhận số nguyên 1..100. rate đọc tần số, get đọc thuộc tính/trạng thái enable. Mọi yêu cầu được gửi bằng SCMI Clock protocol 0x14 và nhận status từ firmware.'

Add-H1 '6. Luồng gửi lệnh và nhận kết quả'
Add-P 'Ví dụ với pmu_gpio 0 on:'
Add-P '1. Lệnh tạo payload gồm GPIO ID 0 và giá trị 1.'
Add-P '2. SCMI framework tạo header protocol 0x80, message ID 3 và ghi yêu cầu vào shared BRAM.'
Add-P '3. Driver mailbox xóa completion cũ, dùng memory barrier rồi ghi request.'
Add-P '4. RTL đưa IRQ lên Ibex; firmware thức khỏi WFI và vào hàm xử lý ngắt.'
Add-P '5. Firmware kiểm tra header, chiều dài và tham số, sau đó cập nhật GPIO0.'
Add-P '6. Firmware ghi status=0, đánh dấu kênh rảnh và đặt completion.'
Add-P '7. U-Boot polling thấy completion, đọc payload phản hồi và in “PMU GPIO0: on”.'
Add-P 'Hai lớp lỗi được phân biệt: lỗi transport/framework ở phía U-Boot và status SCMI do server trả về. Điều này giúp xác định lỗi đường truyền khác với lỗi tham số hoặc lệnh không hỗ trợ.'

Add-H1 '7. Nút S2 và quá trình khởi động lại'
Add-P 'S2 được khai báo tại PS MIO20, active-high, có pulldown ngoài. U-Boot đăng ký cyclic polling; thao tác nhả rồi nhấn S2 gọi zynq_slcr_cpu_reset(). Reset đưa hệ thống về BootROM để FSBL được chạy lại và bitstream được nạp lại.'
Add-P 'Cơ chế này nằm trong U-Boot. Sau khi Linux đã khởi động, U-Boot không còn thực thi nên S2 chỉ tiếp tục hoạt động nếu Linux có driver hoặc dịch vụ riêng tương ứng. Bản cập nhật hiện tại không build lại image Linux.'

Add-H1 '8. Cập nhật BOOT.BIN qua JTAG'
Add-P 'Lệnh jtag_sd_update trong U-Boot chỉ ghi đè BOOT.BIN trên phân vùng FAT của thẻ SD. Quy trình không sao lưu và không thay đổi image.ub hoặc boot.scr. Dữ liệu được truyền vào DDR tại 0x08000000, mô tả giao dịch đặt tại 0x07FFF000, giới hạn 32 MiB. CRC32 và đọc lại được dùng để kiểm tra.'
Add-Code 'Trên U-Boot: jtag_sd_update'
Add-Code 'Trên Windows: vivado\ibex_min\jtag-copy-boot-to-sd.cmd'
Add-P 'Sau khi U-Boot báo hoàn tất, thực hiện reset nguồn hoặc reset CPU để BootROM nạp BOOT.BIN mới. Không rút thẻ hoặc ngắt nguồn trong lúc đang ghi.'

Add-H1 '9. Quy trình build và đóng gói đã dùng'
Add-P 'Firmware Ibex được biên dịch bằng toolchain RISC-V; file ELF/binary được chuyển thành firmware.hex và nhúng vào RTL. Vivado tổng hợp thiết kế ibex_min để sinh bitstream. FSBL được build từ hardware description tương ứng. Script build-client.sh đưa driver, command và device tree tùy biến vào cây U-Boot, bật các cấu hình SCMI/mailbox/cyclic cần thiết rồi build u-boot-ibex.elf. Cuối cùng Bootgen đóng gói FSBL, bitstream và U-Boot thành BOOT.BIN.'
Add-P 'Trong lần cập nhật gần nhất, chỉ BOOT.BIN cần được chép lại. image.ub và boot.scr của PetaLinux không bị thay đổi, do đó không cần chờ build lại toàn bộ 4310 task để kiểm tra phần U-Boot/SCMI này.'

Add-H1 '10. Kiểm tra nghiệm thu đề xuất trên bo'
Add-P '1. Mở UART, cấp nguồn và xác nhận FSBL chuyển sang U-Boot bình thường.'
Add-P '2. Dừng autoboot trong 3 giây nếu cần thao tác thủ công.'
Add-P '3. Chạy ibexinit; xác nhận có “Ibex SCMI ready” và không có timeout.'
Add-P '4. Chạy pmu_gpio 0 on/off/get; quan sát LED6 xanh và kết quả đọc lại.'
Add-P '5. Chạy GPIO1..4; đo DATA1 chân 5..8 và so sánh với get.'
Add-P '6. Chạy pmu_clock set 1, pmu_clock on; quan sát LED6 đỏ. Lặp lại ở 10 Hz và 100 Hz; dùng oscilloscope khi tần số cao.'
Add-P '7. Chạy pmu_clock rate/get; xác nhận rate và enable khớp cấu hình.'
Add-P '8. Thử giá trị clock 0 và 101; xác nhận lệnh bị từ chối và trạng thái cũ không đổi.'
Add-P '9. Nhả rồi nhấn S2 khi còn ở U-Boot; xác nhận quay lại BootROM/FSBL và PL được nạp lại.'
Add-P '10. Cho autoboot Linux; xác nhận image.ub cũ vẫn khởi động với BOOT.BIN mới.'

Add-H1 '11. Giới hạn và lưu ý vận hành'
Add-Bullet 'Tài liệu mã nguồn cũ có đoạn mô tả driver tự cấu hình clock/reset; phiên bản hiện tại ưu tiên kiểm tra và kết nối với firmware đã chạy từ FSBL.'
Add-Bullet 'Không truy cập md.l vào AXI PL trước khi phần cứng và clock sẵn sàng; một slave bị reset có thể làm bus bị treo.'
Add-Bullet 'SCMI completion phía PS dùng polling; hiện chưa dùng IRQ từ PL sang GIC của PS.'
Add-Bullet 'S2 reset của U-Boot không còn được polling sau khi chuyển quyền điều khiển cho Linux.'
Add-Bullet 'BOOT.BIN, bitstream, FSBL và U-Boot phải cùng một phiên bản RTL để tránh sai địa chỉ, clock hoặc device tree.'

Add-H1 '12. Danh mục mã nguồn liên quan'
Add-Code 'vivado\ibex_min\ibex_min_top.v                 Top-level và clock 25 MHz'
Add-Code 'vivado\ibex_min\ibex_ps_bd.tcl                 PS, FCLK và địa chỉ AXI'
Add-Code 'vivado\ibex_min\rtl\ibex_soc.v                 SoC, mailbox, GPIO, clock LED'
Add-Code 'vivado\ibex_min\firmware\server.c              SCMI server trên Ibex'
Add-Code 'vivado\ibex_min\firmware\scmi_protocols.h      Protocol/message/register IDs'
Add-Code 'vivado\ibex_min\uboot\ibex-mbox.c              Driver mailbox U-Boot'
Add-Code 'vivado\ibex_min\uboot\ibex-gpio.c              ibexinit/pmu_gpio/pmu_clock'
Add-Code 'vivado\ibex_min\uboot\ibex-scmi.dtsi           Device tree SCMI'
Add-Code 'vivado\ibex_min\uboot\s2-reset.c               Reset bằng nút S2'
Add-Code 'vivado\ibex_min\uboot\jtag-sd-update.c         Ghi BOOT.BIN từ DDR xuống SD'
Add-Code 'vivado\ibex_min\uboot\build-client.sh          Build U-Boot tùy biến'
Add-Code 'vivado\ibex_min\jtag-copy-boot-to-sd.ps1       Script JTAG phía máy tính'

Add-H1 '13. Kết luận'
Add-P 'Thiết kế đã tạo được một kênh quản lý hoàn chỉnh giữa U-Boot trên PS và firmware Ibex trong PL. Clock và phần cứng được hình thành từ giai đoạn FSBL; U-Boot khởi tạo SCMI theo yêu cầu, gửi lệnh qua shared memory/mailbox, nhận kết quả và đọc lại trạng thái. GPIO, clock LED, S2 reset và cập nhật riêng BOOT.BIN đã được tích hợp vào luồng boot của dự án. Bước còn lại là chạy bộ kiểm tra nghiệm thu trên bo với BOOT.BIN mới và lưu log UART làm bằng chứng xác nhận.'

Add-Raw '}'

$fullPath = [System.IO.Path]::GetFullPath($OutputPath)
[System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($fullPath)) | Out-Null
[System.IO.File]::WriteAllText($fullPath, $rtf.ToString(), [System.Text.Encoding]::ASCII)
Write-Output $fullPath
