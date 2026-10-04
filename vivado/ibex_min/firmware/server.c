#include "scmi_protocols.h"

/*
 * FIRMWARE CHẠY TRÊN IBEX TRONG PL, KHÔNG PHẢI CODE CHẠY TRÊN PS.
 *
 * Luồng làm việc:
 *   1. PS/U-Boot ghi yêu cầu vào shared memory, đặt channel busy và request=1.
 *   2. request kích ngắt Ibex, đánh thức CPU khỏi wfi để xử lý yêu cầu.
 *   3. Ibex đặt channel free=1, rồi completion=1 để PS biết đã xử lý xong.
 *
 * Server thử nghiệm: Base protocol 0x10 v2.0 để nhận diện server;
 * protocol riêng 0x80 v1.0: GPIO0=LED6, GPIO1..4=DATA1 pins 5..8.
 * Clock protocol 0x14 v1.0: bật/tắt clock nhấp nháy LED6 đỏ, clock ID 0.
 * Ibex dùng ngắt; PS vẫn polling completion. Chưa có thông báo bất đồng bộ.
 *
 * Địa chỉ trong file này là địa chỉ Ibex nhìn thấy. PS nhìn cùng shared
 * memory tại 0x43C01000 và các thanh ghi mailbox tại 0x43C00000.
 *
 * Layout SCMI SMT: mỗi SHM[n] là một word 32 bit, tức 4 byte:
 *   SHM[0]    : reserved, chưa dùng.
 *   SHM[SCMI_SMT_CHANNEL_STATUS]    : channel_status; bit 0=1: rảnh/đã trả lời; =0: đang xử lý.
 *   SHM[2..3] : reserved, chưa dùng.
 *   SHM[4]    : flags; server không phát ngắt về PS theo flags.
 *   SHM[SCMI_SMT_LENGTH]    : length, số BYTE của message header + payload.
 *   SHM[SCMI_SMT_HEADER]    : message header: message ID, type, protocol ID và token.
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
 * Offset dùng: 0=request, 4=completion, 8=ready, 0x10=GPIO bits 0..4,
 * 0x14=trap cause, 0x1c=bộ đếm số ngắt mailbox đã xử lý.
 * Hậu tố u của hằng số nghĩa là unsigned (không dấu). */
#define REG(n) (*(volatile u32 *)(0x30000000u + (n)))
/* Con trỏ đầu shared memory 4 KiB; SHM[n] truy cập base + n*4 byte. */
#define SHM ((volatile u32 *)0x20000000u)
/* Dấu hiệu "IBEX" dạng số để PS biết firmware đã khởi động. */
#define READY 0x49424558u
#define GPIO_COUNT 5u

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
    for(i=0;i<SCMI_BASE_NAME_LENGTH_MAX;i++) out[i]=0;
    /* Chép tối đa 15 ký tự, dừng sớm nếu s[i] là '\0' (giá trị 0).
     * && nghĩa là phải đúng cả hai điều kiện; byte cuối vẫn giữ bằng 0. */
    for(i=0;i<SCMI_BASE_NAME_LENGTH_MAX-1 && s[i];i++) out[i]=(unsigned char)s[i];
}

/* protocol: mã nhóm lệnh; id: mã lệnh trong nhóm.
 * Trả về 1 nếu hỗ trợ message đó, 0 nếu không hỗ trợ. */
static int supported(u32 protocol, u32 id) {
    /* Base hỗ trợ ID 0..7; so sánh id<=7 trả về giá trị đúng/sai 1/0. */
    if(protocol==SCMI_PROTOCOL_ID_BASE) return id<=SCMI_BASE_DISCOVER_AGENT;
    /* GPIO riêng hỗ trợ ID 0..4. */
    if(protocol==SCMI_PROTOCOL_ID_GPIO) return id<=SCMI_GPIO_GET;
    if(protocol==SCMI_PROTOCOL_ID_CLOCK)
        return id<=SCMI_CLOCK_CONFIG_SET;
    return 0; /* Mọi protocol khác đều không hỗ trợ. */
}

/* Xử lý một yêu cầu đã có trong shared memory; không có tham số truyền vào.
 * Hàm xử lý ngắt gọi khi channel_status bit 0 đang bằng 0. */
static void process(void) {
    /* length: độ dài BYTE của message gồm header 4 byte + payload.
     * header: word chứa các trường mã hóa của yêu cầu. */
    u32 length=SHM[SCMI_SMT_LENGTH], header=SHM[SCMI_SMT_HEADER];
    /* protocol: lấy 8 bit [17:10]; >> dịch phải, &255 giữ 8 bit thấp.
     * id: lấy 8 bit [7:0], tức message ID.
     * Không ghi lại SHM[SCMI_SMT_HEADER], nên token của PS được giữ nguyên khi trả lời. */
    u32 protocol=SCMI_HEADER_PROTOCOL_ID(header), id=SCMI_HEADER_MESSAGE_ID(header);
    /* arg0/arg1: hai word tham số đầu, lưu trước khi ghi đè payload yêu cầu.
     * Nếu message không có tham số, chúng có thể là dữ liệu cũ; chỉ dùng
     * ở nhánh lệnh đã kiểm tra length đủ dài.
     * words: số WORD payload phản hồi, gồm status; mặc định chỉ 1 word. */
    u32 arg0=SHM[SCMI_SMT_PAYLOAD], arg1=SHM[SCMI_SMT_PAYLOAD+1], words=1;
    /* & lấy địa chỉ; out trỏ vào đầu payload để viết phản hồi tại chỗ.
     * out[0]=status; out[1...] là dữ liệu trả thêm. */
    volatile u32 *out=&SHM[SCMI_SMT_PAYLOAD];
    /* status mặc định 0=SCMI_SUCCESS; -1=NOT_SUPPORTED,
     * -2=INVALID_PARAMETERS, -3=NOT_FOUND. */
    s32 status=SCMI_SUCCESS;

    /* Cần ít nhất header 4 byte; message không được vượt vùng shared memory.
     * Trước message header có 24 byte SMT metadata, nên tối đa 4096-24 byte.
     * Mask 0x300 lấy bit [9:8] (message type); chỉ nhận command type 0.
     * || là "hoặc": vi phạm một trong các điều kiện thì trả -2. */
    if(length<SCMI_HEADER_SIZE_BYTES || length>SCMI_SMT_SIZE_BYTES-SCMI_SMT_METADATA_BYTES || SCMI_HEADER_MESSAGE_TYPE(header)!=SCMI_MESSAGE_TYPE_COMMAND) status=SCMI_INVALID_PARAMETERS;
    /* != nghĩa là khác; từ chối protocol ngoài Base và GPIO riêng. */
    else if(protocol!=SCMI_PROTOCOL_ID_BASE && protocol!=SCMI_PROTOCOL_ID_GPIO && protocol!=SCMI_PROTOCOL_ID_CLOCK) status=SCMI_NOT_SUPPORTED;
    /* ! đảo đúng/sai: supported() trả 0 thì trả lỗi không hỗ trợ. */
    else if(!supported(protocol,id)) status=SCMI_NOT_SUPPORTED;
    /* ID 0: PROTOCOL_VERSION, dùng chung cho các protocol. */
    else if(id==SCMI_PROTOCOL_VERSION) {
        /* A ? B : C chọn B khi A đúng, chọn C khi A sai.
         * Version: major ở 16 bit cao, minor ở 16 bit thấp.
         * Base=2.0; Clock và GPIO riêng=1.0. */
        out[1]=protocol==SCMI_PROTOCOL_ID_BASE ? SCMI_BASE_PROTOCOL_VERSION :
               protocol==SCMI_PROTOCOL_ID_CLOCK ? SCMI_CLOCK_PROTOCOL_VERSION : SCMI_GPIO_PROTOCOL_VERSION;
        words=2; /* Payload gồm status và version, mỗi phần 1 word. */
    }
    /* ID 1: PROTOCOL_ATTRIBUTES, mô tả khả năng của protocol. */
    else if(id==SCMI_PROTOCOL_ATTRIBUTES) {
        /* Base: 2 agent (platform và PS) ở bit [15:8],
         * 2 protocol ngoài Base ở bit [7:0]: Clock 0x14 và GPIO 0x80.
         * GPIO riêng báo số ngõ ra hỗ trợ. */
        out[1]=protocol==SCMI_PROTOCOL_ID_BASE ? (2u<<8)|2u :
               protocol==SCMI_PROTOCOL_ID_CLOCK ? 1u : GPIO_COUNT;
        words=2; /* Payload gồm status và attributes. */
    }
    /* ID 2: MESSAGE_ATTRIBUTES; hỏi một message ID có được hỗ trợ không. */
    else if(id==SCMI_PROTOCOL_MESSAGE_ATTRIBUTES) {
        if(length<8) status=SCMI_INVALID_PARAMETERS; /* Cần header 4 byte + message ID 4 byte. */
        /* arg0 là message ID cần hỏi; không có thì trả NOT_FOUND. */
        else if(!supported(protocol,arg0)) status=SCMI_NOT_FOUND;
        else {
            out[1]=0; /* Message tồn tại, không có cờ thuộc tính bổ sung. */
            words=2; /* Status + attributes. */
        }
    } else if(protocol==SCMI_PROTOCOL_ID_BASE) { /* Những lệnh còn lại của Base protocol. */
        switch(id) { /* Chọn nhánh dựa trên message ID. */
        case SCMI_BASE_DISCOVER_VENDOR: /* BASE_DISCOVER_VENDOR. */
            name(&out[1],"EBAZ4205"); /* Ghi tên 16 byte sau word status. */
            words=5; /* 1 word status + 4 word tên. */
            break; /* Thoát switch, không chạy sang case tiếp theo. */
        case SCMI_BASE_DISCOVER_SUB_VENDOR: /* BASE_DISCOVER_SUB_VENDOR. */
            name(&out[1],"Ibex"); /* Ghi tên thành phần phụ 16 byte. */
            words=5; /* Status + tên. */
            break;
        case SCMI_BASE_DISCOVER_IMPL_VERSION: /* BASE_DISCOVER_IMPLEMENTATION_VERSION. */
            out[1]=1; /* Phiên bản implementation do mình tự quy định là 1. */
            words=2; /* Status + phiên bản. */
            break;
        case SCMI_BASE_DISCOVER_LIST_PROTOCOLS: /* BASE_DISCOVER_LIST_PROTOCOLS. */
            /* arg0 là số protocol cần bỏ qua khi lấy tiếp danh sách. */
            if(length<8) status=SCMI_INVALID_PARAMETERS; /* Thiếu tham số skip 4 byte. */
            else if(arg0>2) status=SCMI_INVALID_PARAMETERS;
            else {
                /* Packed byte IDs: Clock first, then project GPIO. */
                out[1]=2-arg0;
                out[2]=arg0==0 ? SCMI_PROTOCOL_ID_CLOCK|(SCMI_PROTOCOL_ID_GPIO<<8) :
                       arg0==1 ? SCMI_PROTOCOL_ID_GPIO : 0;
                words=3; /* Status + count + word chứa ID/đệm. */
            }
            break;
        case SCMI_BASE_DISCOVER_AGENT: /* BASE_DISCOVER_AGENT: hỏi ID/tên một agent. */
            if(length<8) status=SCMI_INVALID_PARAMETERS; /* Cần tham số agent ID 4 byte. */
            else {
                /* 0xffffffff là ID đặc biệt: hỏi agent đang gọi, ở đây PS ID 1. */
                if(arg0==0xffffffffu) arg0=1;
                if(arg0>1) status=SCMI_NOT_FOUND; /* Chỉ có agent 0 và 1. */
                else {
                    out[1]=arg0; /* Trả lại ID agent đã xác định. */
                    /* Agent 0=platform; agent 1=PS chạy U-Boot. */
                    name(&out[2],arg0==0 ? "platform" : "U-Boot");
                    words=6; /* Status + ID + 4 word tên. */
                }
            }
            break;
        case SCMI_BASE_NOTIFY_ERRORS: /* BASE_NOTIFY_ERRORS: chưa hỗ trợ.
                 * Nhánh này hiện không chạy vì supported() chỉ cho Base ID<=7;
                 * ID 8 đã bị trả -1 ở bước kiểm tra phía trên. */
            status=SCMI_NOT_SUPPORTED;
            break;
        }
    } else if(protocol==SCMI_PROTOCOL_ID_CLOCK) {
        if(id==SCMI_CLOCK_RATE_SET) {
            /* SCMI wire order: flags, clock ID, rate low, rate high.
             * Only synchronous exact-rate requests (flags=0) are supported. */
            if(length<20 || arg0!=0) status=SCMI_INVALID_PARAMETERS;
            else if(arg1!=SCMI_CLOCK_LED6_ID) status=SCMI_NOT_FOUND;
            else if(out[3]!=0 || out[2]<SCMI_CLOCK_LED6_MIN_HZ ||
                    out[2]>SCMI_CLOCK_LED6_MAX_HZ) status=SCMI_INVALID_PARAMETERS;
            else REG(IBEX_REG_LED_RATE)=out[2];
        } else if(length<8) status=SCMI_INVALID_PARAMETERS;
        else if(arg0!=SCMI_CLOCK_LED6_ID) status=SCMI_NOT_FOUND;
        else switch(id) {
        case SCMI_CLOCK_ATTRIBUTES:
            out[1]=REG(IBEX_REG_LED_CLOCK)&SCMI_CLOCK_ENABLE;
            name(&out[2],"led6_red");
            words=6; /* status, attributes, 16-byte name */
            break;
        case SCMI_CLOCK_DESCRIBE_RATES:
            if(length<12 || arg1!=0) status=SCMI_INVALID_PARAMETERS;
            else {
                out[1]=0x1003; /* Range format: min, max, step; none remaining. */
                out[2]=SCMI_CLOCK_LED6_MIN_HZ; out[3]=0;
                out[4]=SCMI_CLOCK_LED6_MAX_HZ; out[5]=0;
                out[6]=1; out[7]=0;
                words=8;
            }
            break;
        case SCMI_CLOCK_RATE_GET:
            out[1]=REG(IBEX_REG_LED_RATE); out[2]=0;
            words=3; /* status + 64-bit rate, unchanged when gated */
            break;
        case SCMI_CLOCK_CONFIG_SET:
            if(length<12 || (arg1&~SCMI_CLOCK_ENABLE)) status=SCMI_INVALID_PARAMETERS;
            else REG(IBEX_REG_LED_CLOCK)=arg1;
            break;
        }
    } else { /* GPIO protocol */
        if(length<8) status=SCMI_INVALID_PARAMETERS; /* SET/GET đều cần tham số GPIO ID 4 byte. */
        else if(arg0>=GPIO_COUNT) status=SCMI_NOT_FOUND; /* GPIO ID ngoài 0..4. */
        else if(id==SCMI_GPIO_SET) { /* GPIO_SET: arg0=GPIO ID; arg1=giá trị cần ghi. */
            /* SET cần header + 2 tham số = 12 byte; giá trị chỉ cho phép 0/1. */
            if(length<12 || arg1>1) status=SCMI_INVALID_PARAMETERS;
            /* Chỉ đổi bit được chọn; giữ nguyên các GPIO còn lại.
             * RTL đảo GPIO0 cho LED active-low; DATA GPIO dùng mức trực tiếp. */
            else REG(0x10)=(REG(0x10)&~(1u<<arg0))|(arg1<<arg0);
        } else if(id==SCMI_GPIO_GET) { /* GPIO_GET: đọc trạng thái GPIO0. */
            out[1]=(REG(0x10)>>arg0)&1u; /* Đọc bit theo GPIO ID. */
            words=2; /* Payload gồm status và giá trị GPIO. */
        }
    }

    /* Ghi status vào word đầu. Ép sang u32 biểu diễn mã lỗi dưới dạng word
     * 32 bit: ví dụ -2 thành 0xfffffffe; phía PS đọc lại là số có dấu. */
    out[0]=(u32)status;
    if(status) words=1; /* Nếu lỗi thì chỉ trả status, bỏ dữ liệu trả thêm. */
    SHM[SCMI_SMT_LENGTH]=SCMI_HEADER_SIZE_BYTES+4*words; /* Độ dài BYTE: header 4 byte + payload words*4 byte. */
    fence(); /* Công bố payload/length trước khi công bố channel hoàn tất. */
    SHM[SCMI_SMT_CHANNEL_STATUS]=SCMI_SHMEM_CHAN_STAT_CHANNEL_FREE; /* Bit 0=1: channel free; ghi 1 cũng xóa các bit status khác. */
    fence(); /* Công bố channel free trước completion doorbell. */
    REG(4)=1; /* Báo hoàn tất; PS polling thanh ghi mailbox này. */
}

/* Hàm phục vụ ngắt machine. GCC tự lưu/khôi phục các thanh ghi cần bảo vệ
 * và sinh lệnh mret khi kết thúc, để CPU quay lại đoạn main() bị ngắt.
 * start.S đặt vector machine external interrupt (cause 11) trỏ tới hàm này.
 * Khi vào ngắt, phần cứng tạm tắt MIE; mret khôi phục nó, tránh ngắt lồng. */
__attribute__((interrupt("machine"))) void scmi_irq(void) {
    u32 cause; /* mcause: bit 31=ngắt; các bit thấp=mã nguyên nhân. */
    /* %0 là toán hạng đầu; "=r" yêu cầu một thanh ghi đầu ra cho biến cause. */
    __asm__ volatile("csrr %0, mcause" : "=r"(cause)); /* Đọc CSR vào biến C. */
    if(cause!=0x8000000bu) { /* Chỉ chấp nhận machine external IRQ số 11. */
        REG(0x14)=cause; /* Lưu nguyên nhân bất thường để PS xem. */
        for(;;) {} /* Dừng để chẩn đoán; không tiếp tục xử lý message sai. */
    }
    fence(); /* Đọc payload sau khi đã nhận ngắt request. */
    REG(0)=0; /* Xóa request, đồng thời hạ IRQ mức trong RTL. */
    REG(0x1c)=REG(0x1c)+1; /* Tăng bộ đếm ngắt để kiểm tra trên bo. */
    /* Chỉ xử lý khi PS đã đặt channel busy, tức bit 0=0.
     * Doorbell khi channel vẫn free được xác nhận/xóa nhưng không trả message. */
    if(!(SHM[SCMI_SMT_CHANNEL_STATUS]&SCMI_SHMEM_CHAN_STAT_CHANNEL_FREE)) process();
}

/* Điểm bắt đầu phần C, được start.S gọi sau khi đã chuẩn bị stack và RAM. */
void main(void) {
    REG(0x10)=0; /* LED6 tắt, DATA1 GPIO1..4 mức thấp. */
    REG(IBEX_REG_LED_CLOCK)=0;
    SHM[SCMI_SMT_CHANNEL_STATUS]=SCMI_SHMEM_CHAN_STAT_CHANNEL_FREE; /* Đánh dấu channel rảnh để PS gửi yêu cầu đầu tiên. */
    REG(0x1c)=0; /* Bộ đếm ngắt bắt đầu từ 0. */
    /* mie.MEIE (bit 11) bật nguồn ngắt machine external, nối với request.
     * "r" đưa giá trị 1<<11 vào thanh ghi đầu vào; csrw ghi nó vào CSR mie. */
    __asm__ volatile("csrw mie, %0" :: "r"(1u<<11) : "memory");
    /* mstatus.MIE (bit 3) cho phép CPU nhận ngắt ở mức toàn cục. */
    __asm__ volatile("csrsi mstatus, 8" ::: "memory");
    fence(); /* Công bố các bước khởi tạo trước ready. */
    REG(8)=READY; /* Báo PS có thể gửi yêu cầu sau khi ngắt đã được bật. */
    /* Không polling mailbox: wfi chờ ngắt; scmi_irq() xử lý yêu cầu.
     * IRQ là mức, giữ bởi request cho đến khi ISR xóa, nên không mất xung.
     * WFI không tự tắt clock toàn bộ PL; nó cho lõi CPU ngừng phát lệnh. */
    for(;;) {
        __asm__ volatile("wfi" ::: "memory"); /* Chờ IRQ tiếp theo. */
    }
}
