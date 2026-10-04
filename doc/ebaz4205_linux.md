EBAZ4205
┌─────────────────────────────────────────────┐
│ Zynq-7010                                   │
│                                             │
│ PS - Cortex-A9                              │
│ ┌──────────────────────────┐                │
│ │ Uboot                    │                │
│ │                          │                │
│ │ Application              │                │
│ │      │                   │                │
│ │ Uboot Kernel             │                │
│ │      │                   │                │
│ │ SCMI Core                │                │
│ │      │                   │                │
│ │ Custom SCMI Transport    │                │
│ │      │                   │                │
│ └──────┼───────────────────┘                │
│        │ AXI / SPI / Mailbox                │
│        ▼                                    │
│ PL                                          │
│ ┌──────────────────────────┐                │
│ │ Transport RTL            │                │
│ │      │                   │                │
│ │ Ibex CPU                 │                │
│ │      │                   │                │
│ │ PMU Firmware             │                │
│ │      │                   │                │
│ │ SCMI Protocol Handler    │                │
│ └──────────────────────────┘                │
└─────────────────────────────────────────────┘


mkdir -p ~/ebaz-dev
cd ~/ebaz-dev

git clone --branch v2025.10 --depth 1 \
    --recurse-submodules --shallow-submodules \
    https://github.com/u-boot/u-boot.git

cd u-boot
export CROSS_COMPILE=arm-linux-gnueabihf-

# Đưa device tree EBAZ4205 vào thư mục DTS của U-Boot
cp dts/upstream/src/arm/xilinx/zynq-ebaz4205.dts arch/arm/dts/

make O=out xilinx_zynq_virt_defconfig

./scripts/config --file out/.config \
    --disable SPL \
    --disable OF_BOARD \
    --enable OF_SEPARATE \
    --set-str DEFAULT_DEVICE_TREE zynq-ebaz4205 \
    --set-str OF_LIST zynq-ebaz4205

make O=out olddefconfig






Tôi đã xác định nguyên nhân lỗi BRAM: AXI có địa chỉ đọc và ghi riêng, còn một cổng BRAM chỉ nhận một địa chỉ mỗi chu kỳ. Tôi đã thêm phân xử giữa đọc/ghi phía PS và giữ dữ liệu ổn định khi PS chưa nhận xong phản hồi.



/*
 * Luồng làm việc:
 *   1. PS/U-Boot ghi yêu cầu vào shared memory, đặt channel busy và request=1.
 *   2. Ibex polling request, đọc yêu cầu và ghi phản hồi vào cùng vùng nhớ.
 *   3. Ibex đặt channel free=1, rồi completion=1 để PS biết đã xử lý xong.
 *
 * Server thử nghiệm: Base protocol 0x10 v2.0 để nhận diện server;
 * protocol riêng 0x80 v1.0 để bật/tắt và đọc GPIO0 (LED6 xanh).
 * Chưa dùng ngắt, thông báo bất đồng bộ, điều khiển nguồn hay hiệu năng.
 *
 * Địa chỉ trong file này là địa chỉ Ibex nhìn thấy. PS nhìn cùng shared
 * memory tại 0x43C01000 và các thanh ghi mailbox tại 0x43C00000.
 *
 * Layout SCMI SMT: mỗi SHM[n] là một word 32 bit, tức 4 byte:
 *   SHM[0]    : reserved, chưa dùng.
 *   SHM[1]    : channel_status; bit 0=1: rảnh/đã trả lời; =0: đang xử lý.
 *   SHM[2..3] : reserved, chưa dùng.
 *   SHM[4]    : flags; server polling này không phát ngắt theo flags.
 *   SHM[5]    : length, số BYTE của message header + payload.
 *   SHM[6]    : message header: message ID, type, protocol ID và token.
 *   SHM[7...] : payload; khi trả lời, word đầu là mã status.
 *
 * Code bare-metal: start.S chuẩn bị stack/RAM rồi gọi main() ở cuối file.
 * Các dấu ngoặc nhọn { } gom câu lệnh thành một khối; dấu ; kết thúc lệnh.
 */

/* u32: tên ngắn cho số nguyên không dấu 32 bit trên toolchain RISC-V này.
 * Dùng cho thanh ghi, word message và bit mask. */
typedef unsigned int u32;
/* s32: số nguyên có dấu 32 bit, dùng cho các mã lỗi SCMI âm. */
typedef int s32;

/* REG(n): đọc/ghi thanh ghi tại địa chỉ 0x30000000 + offset n BYTE.
 * Ép địa chỉ thành con trỏ u32*, rồi * lấy giá trị tại địa chỉ đó.
 * volatile buộc compiler thực hiện truy cập vì phần cứng/PS có thể đổi nó.
 * volatile không tự đảm bảo thứ tự truy cập giữa hai CPU; cần fence().
 * Offset dùng: 0=request, 4=completion, 8=ready, 0x10=GPIO0.
 * Hậu tố u của hằng số nghĩa là unsigned (không dấu). */
#define REG(n) (*(volatile u32 *)(0x30000000u + (n)))
/* Con trỏ đầu shared memory 4 KiB; SHM[n] truy cập base + n*4 byte. */
#define SHM ((volatile u32 *)0x20000000u)
/* Dấu hiệu "IBEX" dạng số để PS biết firmware đã khởi động. */
#define READY 0x49424558u

/* static: hàm chỉ dùng trong file này; void: không trả giá trị.
 * fence iorw,iorw giữ thứ tự truy cập bộ nhớ và I/O trước/sau lệnh này. */
static void fence(void) {
    /* __asm__ chèn assembly RISC-V; volatile giữ lệnh này trong chương trình.
     * "memory" ngăn compiler chuyển truy cập bộ nhớ qua hàng rào.
     * Các dấu : là cú pháp khai báo toán hạng/clobber của inline assembly. */
    __asm__ volatile("fence iorw,iorw" ::: "memory");
}

/* Ghi một tên vào trường SCMI cố định 16 byte.
 * p: địa chỉ đích trong shared memory, ban đầu là con trỏ word 32 bit.
 * s: chuỗi nguồn kết thúc bằng '\0'; const nghĩa là không sửa chuỗi nguồn. */
static void name(volatile u32 *p, const char *s) {
    /* Đổi con trỏ word thành con trỏ byte để chép từng ký tự 8 bit.
     * out là biến cục bộ của name(), khác biến out trong process(). */
    volatile unsigned char *out = (volatile unsigned char *)p;
    unsigned i; /* i là chỉ số byte/ký tự đang xử lý. */
    /* i=0: bắt đầu; i<16: điều kiện lặp; i++: tăng i sau mỗi vòng.
     * Xóa cả 16 byte, đảm bảo có ký tự kết thúc và các byte đệm bằng 0. */
    for(i=0;i<16;i++) out[i]=0;
    /* Chép tối đa 15 ký tự, dừng sớm nếu s[i] là '\0' (giá trị 0).
     * && nghĩa là phải đúng cả hai điều kiện; byte cuối vẫn giữ bằng 0. */
    for(i=0;i<15 && s[i];i++) out[i]=(unsigned char)s[i];
}

/* protocol: mã nhóm lệnh; id: mã lệnh trong nhóm.
 * Trả về 1 nếu hỗ trợ message đó, 0 nếu không hỗ trợ. */
static int supported(u32 protocol, u32 id) {
    /* Base hỗ trợ ID 0..7; so sánh id<=7 trả về giá trị đúng/sai 1/0. */
    if(protocol==0x10) return id<=7;
    /* GPIO riêng hỗ trợ ID 0..4. */
    if(protocol==0x80) return id<=4;
    return 0; /* Mọi protocol khác đều không hỗ trợ. */
}

/* Xử lý một yêu cầu đã có trong shared memory; không có tham số truyền vào.
 * Chỉ gọi khi PS đã gửi request và channel_status bit 0 đang bằng 0. */
static void process(void) {
    /* length: độ dài BYTE của message gồm header 4 byte + payload.
     * header: word chứa các trường mã hóa của yêu cầu. */
    u32 length=SHM[5], header=SHM[6];
    /* protocol: lấy 8 bit [17:10]; >> dịch phải, &255 giữ 8 bit thấp.
     * id: lấy 8 bit [7:0], tức message ID.
     * Không ghi lại SHM[6], nên token của PS được giữ nguyên khi trả lời. */
    u32 protocol=(header>>10)&255, id=header&255;
    /* arg0/arg1: hai word tham số đầu, lưu trước khi ghi đè payload yêu cầu.
     * Nếu message không có tham số, chúng có thể là dữ liệu cũ; chỉ dùng
     * ở nhánh lệnh đã kiểm tra length đủ dài.
     * words: số WORD payload phản hồi, gồm status; mặc định chỉ 1 word. */
    u32 arg0=SHM[7], arg1=SHM[8], words=1;
    /* & lấy địa chỉ; out trỏ vào đầu payload để viết phản hồi tại chỗ.
     * out[0]=status; out[1...] là dữ liệu trả thêm. */
    volatile u32 *out=&SHM[7];
    /* status mặc định 0=SCMI_SUCCESS; -1=NOT_SUPPORTED,
     * -2=INVALID_PARAMETERS, -3=NOT_FOUND. */
    s32 status=0;

    /* Cần ít nhất header 4 byte; message không được vượt vùng shared memory.
     * Trước message header có 24 byte SMT metadata, nên tối đa 4096-24 byte.
     * Mask 0x300 lấy bit [9:8] (message type); chỉ nhận command type 0.
     * || là "hoặc": vi phạm một trong các điều kiện thì trả -2. */
    if(length<4 || length>4096-24 || (header&0x300)) status=-2;
    /* != nghĩa là khác; từ chối protocol ngoài Base và GPIO riêng. */
    else if(protocol!=0x10 && protocol!=0x80) status=-1;
    /* ! đảo đúng/sai: supported() trả 0 thì trả lỗi không hỗ trợ. */
    else if(!supported(protocol,id)) status=-1;
    /* ID 0: PROTOCOL_VERSION, dùng chung cho cả hai protocol. */
    else if(id==0) {
        /* A ? B : C chọn B khi A đúng, chọn C khi A sai.
         * Version: major ở 16 bit cao, minor ở 16 bit thấp.
         * Base 0x00020000=2.0; GPIO riêng 0x00010000=1.0. */
        out[1]=protocol==0x10 ? 0x20000 : 0x10000;
        words=2; /* Payload gồm status và version, mỗi phần 1 word. */
    }
    /* ID 1: PROTOCOL_ATTRIBUTES, mô tả khả năng của protocol. */
    else if(id==1) {
        /* Base: 2 agent (platform và PS) ở bit [15:8],
         * 1 protocol ngoài Base ở bit [7:0], tức GPIO 0x80.
         * << dịch trái; | ghép các trường bit. GPIO riêng báo có 1 GPIO. */
        out[1]=protocol==0x10 ? (2u<<8)|1u : 1u;
        words=2; /* Payload gồm status và attributes. */
    }
    /* ID 2: MESSAGE_ATTRIBUTES; hỏi một message ID có được hỗ trợ không. */
    else if(id==2) {
        if(length<8) status=-2; /* Cần header 4 byte + message ID 4 byte. */
        /* arg0 là message ID cần hỏi; không có thì trả NOT_FOUND. */
        else if(!supported(protocol,arg0)) status=-3;
        else {
            out[1]=0; /* Message tồn tại, không có cờ thuộc tính bổ sung. */
            words=2; /* Status + attributes. */
        }
    } else if(protocol==0x10) { /* Những lệnh còn lại của Base protocol. */
        switch(id) { /* Chọn nhánh dựa trên message ID. */
        case 3: /* BASE_DISCOVER_VENDOR. */
            name(&out[1],"EBAZ4205"); /* Ghi tên 16 byte sau word status. */
            words=5; /* 1 word status + 4 word tên. */
            break; /* Thoát switch, không chạy sang case tiếp theo. */
        case 4: /* BASE_DISCOVER_SUB_VENDOR. */
            name(&out[1],"Ibex"); /* Ghi tên thành phần phụ 16 byte. */
            words=5; /* Status + tên. */
            break;
        case 5: /* BASE_DISCOVER_IMPLEMENTATION_VERSION. */
            out[1]=1; /* Phiên bản implementation do mình tự quy định là 1. */
            words=2; /* Status + phiên bản. */
            break;
        case 6: /* BASE_DISCOVER_LIST_PROTOCOLS. */
            /* arg0 là số protocol cần bỏ qua khi lấy tiếp danh sách. */
            if(length<8) status=-2; /* Thiếu tham số skip 4 byte. */
            else if(arg0>1) status=-2; /* Chỉ có 1 protocol ngoài Base. */
            else {
                out[1]=arg0==0 ? 1 : 0; /* Skip 0: trả 1 ID; skip 1: hết ID. */
                out[2]=0x80; /* ID GPIO riêng ở byte thấp; các byte đệm bằng 0.
                             * Khi count=0, client không sử dụng word ID này. */
                words=3; /* Status + count + word chứa ID/đệm. */
            }
            break;
        case 7: /* BASE_DISCOVER_AGENT: hỏi ID/tên một agent. */
            if(length<8) status=-2; /* Cần tham số agent ID 4 byte. */
            else {
                /* 0xffffffff là ID đặc biệt: hỏi agent đang gọi, ở đây PS ID 1. */
                if(arg0==0xffffffffu) arg0=1;
                if(arg0>1) status=-3; /* Chỉ có agent 0 và 1. */
                else {
                    out[1]=arg0; /* Trả lại ID agent đã xác định. */
                    /* Agent 0=platform; agent 1=PS chạy U-Boot. */
                    name(&out[2],arg0==0 ? "platform" : "U-Boot");
                    words=6; /* Status + ID + 4 word tên. */
                }
            }
            break;
        case 8: /* BASE_NOTIFY_ERRORS: chưa hỗ trợ.
                 * Nhánh này hiện không chạy vì supported() chỉ cho Base ID<=7;
                 * ID 8 đã bị trả -1 ở bước kiểm tra phía trên. */
            status=-1;
            break;
        }
    } else { /* Chỉ còn protocol GPIO 0x80; ID 0/1/2 đã xử lý phía trên. */
        if(length<8) status=-2; /* SET/GET đều cần tham số GPIO ID 4 byte. */
        else if(arg0!=0) status=-3; /* Chỉ có GPIO0, không có GPIO ID khác. */
        else if(id==3) { /* GPIO_SET: arg0=GPIO ID; arg1=giá trị cần ghi. */
            /* SET cần header + 2 tham số = 12 byte; giá trị chỉ cho phép 0/1. */
            if(length<12 || arg1>1) status=-2;
            /* Ghi GPIO0: 1=bật LED xanh, 0=tắt.
             * RTL tự đảo mức cho chân LED active-low; C không đảo lần nữa. */
            else REG(0x10)=arg1;
        } else if(id==4) { /* GPIO_GET: đọc trạng thái GPIO0. */
            out[1]=REG(0x10)&1; /* Lấy bit 0, trả giá trị logic 0 hoặc 1. */
            words=2; /* Payload gồm status và giá trị GPIO. */
        }
    }

    /* Ghi status vào word đầu. Ép sang u32 biểu diễn mã lỗi dưới dạng word
     * 32 bit: ví dụ -2 thành 0xfffffffe; phía PS đọc lại là số có dấu. */
    out[0]=(u32)status;
    if(status) words=1; /* Nếu lỗi thì chỉ trả status, bỏ dữ liệu trả thêm. */
    SHM[5]=4+4*words; /* Độ dài BYTE: header 4 byte + payload words*4 byte. */
    fence(); /* Công bố payload/length trước khi công bố channel hoàn tất. */
    SHM[1]=1; /* Bit 0=1: channel free; ghi 1 cũng xóa các bit status khác. */
    fence(); /* Công bố channel free trước completion doorbell. */
    REG(4)=1; /* Báo hoàn tất; PS polling thanh ghi mailbox này. */
}

/* Điểm bắt đầu phần C, được start.S gọi sau khi đã chuẩn bị stack và RAM. */
void main(void) {
    REG(0x10)=0; /* Khởi động với GPIO0=0, LED6 xanh tắt. */
    SHM[1]=1; /* Đánh dấu channel rảnh để PS gửi yêu cầu đầu tiên. */
    REG(8)=READY; /* Báo firmware sẵn sàng sau các bước khởi tạo trên. */
    /* Vòng lặp vô hạn: ba phần của for đều trống, nên không tự kết thúc.
     * Không dùng ngắt/wfi; CPU liên tục kiểm tra request (polling). */
    for(;;) {
        if(REG(0)&1) { /* Lấy bit 0 của request: bằng 1 là có yêu cầu từ PS. */
            fence(); /* Nhận request trước, rồi mới đọc shared memory. */
            REG(0)=0; /* Xóa request đã nhận để không xử lý lại yêu cầu đó. */
            /* Chỉ xử lý khi PS đã đặt channel busy, tức bit 0=0.
             * Nếu vẫn free thì bỏ qua doorbell này, không tạo phản hồi. */
            if(!(SHM[1]&1)) process();
        }
    }
}




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


flowchart LR
    subgraph PS["PS — ARM chạy U-Boot"]
        CMD["Console<br/>ibexgpio on/off/get"]
        GPIOCMD["uboot/ibex-gpio.c<br/>Tạo yêu cầu protocol 0x80"]
        SCMI["SCMI framework của U-Boot<br/>SCMI agent + mailbox transport"]
        DRV["uboot/ibex-mbox.c<br/>Gửi request, kiểm tra completion"]
        CMD --> GPIOCMD --> SCMI
        SCMI --> DRV
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