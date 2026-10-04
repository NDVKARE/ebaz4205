// SPDX-License-Identifier: GPL-2.0+
/*
 * CODE CHẠY TRÊN PS TRONG U-BOOT
 *
 * File này tạo hai lệnh tại dấu nhắc UART của U-Boot:
 *   ibexinit       : khởi tạo kết nối SCMI với Ibex sau khi boot lên console.
 *   pmu_gpio on    : gửi SCMI để Ibex bật GPIO0/LED6 xanh.
 *   pmu_gpio off   : gửi SCMI để Ibex tắt GPIO0/LED6 xanh.
 *   pmu_gpio get   : hỏi trạng thái GPIO0 mà Ibex đang giữ.
 *   pmu_gpio ID on/off/get: chọn GPIO0..4; GPIO1..4 là DATA1 chân 5..8.
 *
 * Luồng gửi lệnh:
 *   Lệnh U-Boot -> SCMI framework -> mailbox + shared memory -> Ibex.
 *   Ibex xử lý bằng ngắt, ghi phản hồi; PS chờ completion bằng polling.
 * File này không tự ghi chân LED hoặc tự viết các thanh ghi AXI.
 * Driver ibex-mbox.c kiểm tra clock/reset và xử lý mailbox; firmware/server.c trên
 * Ibex đảm nhiệm xử lý yêu cầu SCMI và điều khiển GPIO.
 */

/* Các header cung cấp kiểu dữ liệu, hằng số và khai báo hàm dùng bên dưới. */
/* Đăng ký lệnh U_BOOT_CMD, kiểu cmd_tbl, mã CMD_RET_* và in thông báo. */
#include <command.h>
/* Driver Model (DM): quản lý thiết bị/driver của U-Boot, kiểu udevice. */
#include <dm.h>
/* Giao diện SCMI agent phía PS. */
#include <scmi_agent.h>
/* API xử lý message SCMI qua thiết bị protocol/agent. */
#include <scmi_agent-uclass.h>
/* Các mã protocol chuẩn và cấu trúc scmi_msg. */
#include <scmi_protocols.h>
/* API truy cập nhóm thiết bị uclass của Driver Model. */
#include <dm/uclass.h>
/* API tìm thiết bị đã bind mà chưa bắt buộc probe. */
#include <dm/uclass-internal.h>
/* device_probe(): kích hoạt/khởi tạo một thiết bị. */
#include <dm/device-internal.h>
/* lists_bind_fdt(): chọn driver và bind thiết bị từ node device tree. */
#include <dm/lists.h>
/* dm_root(): thiết bị gốc của cây Driver Model. */
#include <dm/root.h>
/* ofnode: cách U-Boot truy cập node trong device tree. */
#include <dm/ofnode.h>
/* Mã lỗi ENODEV: không tìm thấy/không có thiết bị. */
#include <linux/errno.h>
/* strcmp(): so sánh các chuỗi như "on", "off", "get". */
#include <string.h>

/* Hàm nội bộ: tìm hoặc tạo SCMI agent, rồi đảm bảo thiết bị được khởi tạo.
 * static: chỉ dùng trong file này; int: trả 0 khi thành công, số âm khi lỗi.
 * agent là con trỏ tới con trỏ (**): hàm có thể ghi địa chỉ thiết bị vào biến
 * của bên gọi, chẳng hạn ibex_init_agent(&agent).
 * Bind = tạo/liên kết thiết bị với driver; probe = kích hoạt thiết bị.
 * SCMI post_bind còn thực hiện discovery, nên bind ở đây có thể giao tiếp PL. */
static int ibex_init_agent(struct udevice **agent)
{
    /* node giữ tham chiếu tới node /firmware/scmi trong device tree. */
    ofnode node;
    /* ret là mã kết quả. Tìm agent thứ nhất (index 0) đã bind trong DM.
     * Nếu tìm thấy, hàm ghi con trỏ thiết bị vào *agent; chưa bắt buộc probe. */
    int ret = uclass_find_device(UCLASS_SCMI_AGENT, 0, agent);
    /* ret khác 0 nghĩa là chưa tìm được agent: tiến hành bind thủ công. */
    if (ret) {
        /* Lấy node SCMI. Node này được đặt status="disabled" để không tự
         * discovery/truy cập AXI ngay trong lúc U-Boot đang boot. */
        node = ofnode_path("/firmware/scmi");
        /* ! đảo đúng/sai; nếu node không tồn tại thì trả mã lỗi âm. */
        if (!ofnode_valid(node)) return -ENODEV;
        /* Thông báo trên UART trước bước bind có thể giao tiếp với Ibex. */
        printf("Ibex: binding SCMI after console startup\n");
        /* Bind node vào gốc DM và trả thiết bị qua agent.
         * NULL: không chỉ định driver, chọn theo compatible của node.
         * false: không giới hạn ở các driver dành cho giai đoạn trước relocation.
         * API bind trực tiếp này không áp dụng bước lọc status của quét DT;
         * vì vậy có thể bind node disabled theo yêu cầu của lệnh người dùng. */
        ret = lists_bind_fdt(dm_root(), node, agent, NULL, false);
        /* Có lỗi khi bind thì trả lại nguyên mã lỗi cho bên gọi. */
        if (ret) return ret;
        /* Không có lỗi nhưng không driver nào tạo thiết bị thì vẫn thất bại.
         * *agent là giá trị con trỏ mà bên gọi nhận được. */
        if (!*agent) return -ENODEV;
    }
    /* Đảm bảo agent hoạt động. Nếu đã probe thành công thì DM không khởi tạo
     * lại từ đầu; trả kết quả probe cho bên gọi. */
    return device_probe(*agent);
}

/* Hàm U-Boot gọi khi người dùng gõ ibexinit.
 * cmdtp: thông tin lệnh; flag: cờ cách gọi; argc: số đối số;
 * argv: mảng chuỗi đối số, argv[0] là "ibexinit".
 * Chữ ký hàm là quy ước U-Boot; hàm này không cần dùng các tham số đó.
 * char *const argv[] nghĩa là các phần tử con trỏ argv không bị gán lại
 * qua tham số này; không đồng nghĩa nội dung từng chuỗi là const. */
static int do_ibexinit(struct cmd_tbl *cmdtp, int flag, int argc, char *const argv[])
{
    /* agent nhận địa chỉ thiết bị SCMI phía PS sau khi khởi tạo. */
    struct udevice *agent;
    /* & lấy địa chỉ biến agent để hàm bên trong có thể cập nhật con trỏ này. */
    int ret = ibex_init_agent(&agent);
    /* Khởi tạo không thành công thì in mã lỗi và báo lệnh thất bại. */
    if (ret) {
        /* %d in số nguyên có dấu; \n xuống dòng trên console. */
        printf("Ibex SCMI initialization failed (%d)\n", ret);
        /* Mã thất bại của lệnh U-Boot, khác với mã lỗi SCMI trong payload. */
        return CMD_RET_FAILURE;
    }
    /* Chỉ in ready sau khi khởi tạo/probe agent thành công. */
    printf("Ibex SCMI ready\n");
    /* Trả mã thành công cho bộ xử lý lệnh U-Boot. */
    return CMD_RET_SUCCESS;
}

/* Đăng ký lệnh vào bảng lệnh của U-Boot:
 * ibexinit = tên; 1 = tối đa 1 đối số, tính cả tên lệnh;
 * 0 = không tự lặp khi người dùng nhấn Enter ở dòng trống;
 * do_ibexinit = hàm xử lý; hai chuỗi cuối là mô tả và trợ giúp tham số. */
U_BOOT_CMD(ibexinit,1,0,do_ibexinit,"initialize Ibex SCMI after boot", "");

/* Hàm xử lý pmu_gpio on/off/get. Các tham số có cùng ý nghĩa như trên.
 * argc phải là 2: argv[0]="pmu_gpio", argv[1]="on", "off" hoặc "get". */
static int do_pmu_gpio(struct cmd_tbl *cmdtp, int flag, int argc, char *const argv[])
{
    /* agent: thiết bị SCMI agent; base: thiết bị Base protocol, dùng làm
     * điểm truy cập channel đã có. Chúng là con trỏ thiết bị, không phải
     * địa chỉ thanh ghi AXI hay con trỏ tới CPU Ibex. */
    struct udevice *agent, *base;
    /* u32 là số không dấu 32 bit. in là payload gửi đi, khởi tạo bằng 0.
     * in[0]=GPIO ID 0..4; in[1]=giá trị cần SET (0 tắt, 1 bật). */
    u32 in[2]={0,0};
    /* out là payload phản hồi: status có dấu 32 bit, value không dấu 32 bit.
     * status=0: thành công; status âm: lỗi do firmware SCMI trả về.
     * value chỉ có ý nghĩa với GET; SET chỉ nhận word status đầu tiên. */
    struct { s32 status; u32 value; } out={0,0};
    /* msg mô tả yêu cầu cho SCMI framework:
     * protocol_id=0x80: GPIO protocol riêng của mình, không phải Base 0x10.
     * in_msg/out_msg: địa chỉ hai buffer trong RAM PS, ép thành con trỏ byte.
     * (u8 *)&out lấy địa chỉ struct rồi nhìn nó như dãy byte.
     * Các trường chưa ghi trong initializer tự được khởi tạo bằng 0. */
    struct scmi_msg msg={.protocol_id=0x80, .in_msg=(u8 *)in,
                        .out_msg=(u8 *)&out};
    /* ret giữ mã lỗi ở lớp khởi tạo/transport; khác out.status của server. */
    int ret;
    const char *action;
    /* Sai số đối số thì yêu cầu U-Boot hiện cách dùng lệnh. */
    if(argc!=2 && argc!=3) return CMD_RET_USAGE;
    /* Giữ cú pháp cũ: pmu_gpio on/off/get mặc định GPIO0.
     * Cú pháp mới: pmu_gpio <0..4> on/off/get. Chỉ nhận đúng một chữ số. */
    if(argc==3) {
        if(argv[1][0]<'0' || argv[1][0]>'4' || argv[1][1])
            return CMD_RET_USAGE;
        in[0]=argv[1][0]-'0';
    }
    action=argv[argc-1];
    /* strcmp trả 0 khi hai chuỗi giống nhau; !strcmp vì vậy đúng khi là get. */
    if(!strcmp(action,"get")) {
        msg.message_id=4; /* Message ID 4 của protocol 0x80 = GPIO_GET. */
        msg.in_msg_sz=4; /* Gửi GPIO ID 1 word = 4 BYTE. */
        msg.out_msg_sz=8; /* Nhận status + value = 8 BYTE. */
    /* || nghĩa là "hoặc": chấp nhận on hay off. */
    } else if(!strcmp(action,"on") || !strcmp(action,"off")) {
        /* on làm biểu thức bằng 1; off làm biểu thức bằng 0. */
        in[1]=!strcmp(action,"on");
        msg.message_id=3; /* Message ID 3 của protocol 0x80 = GPIO_SET. */
        msg.in_msg_sz=8; /* GPIO ID + giá trị = 2 word = 8 BYTE. */
        msg.out_msg_sz=4; /* SET chỉ nhận status 1 word = 4 BYTE. */
    /* Đối số khác on/off/get thì hiện cách dùng, không gửi message. */
    } else return CMD_RET_USAGE;
    /* Tự khởi tạo agent nếu chưa chạy ibexinit, hoặc dùng lại agent hiện có. */
    ret=ibex_init_agent(&agent);
    if(ret) {
        printf("SCMI agent unavailable (%d)\n",ret); /* In lỗi khởi tạo. */
        return CMD_RET_FAILURE; /* Kết thúc lệnh, không gửi SCMI. */
    }
    /* Lấy thiết bị Base đã được bind/discovery trong lúc khởi tạo.
     * Chỉ mượn channel của Base; msg.protocol_id vẫn là 0x80 nên yêu cầu
     * được gửi tới GPIO protocol. Không cần driver GPIO protocol riêng ở DM. */
    base=scmi_get_protocol(agent,SCMI_PROTOCOL_ID_BASE);
    /* Không tìm được thiết bị Base thì không có điểm truy cập channel. */
    if(!base) return CMD_RET_FAILURE;
    /* Gửi message và chờ phản hồi: framework chép payload vào shared memory,
     * driver kích request/IRQ, PS chờ completion, rồi chép payload về out.
     * msg.in_msg_sz/out_msg_sz là độ dài payload, không tính SCMI header.
     * Khi trả về, framework cập nhật out_msg_sz thành độ dài payload nhận. */
    printf("PMU GPIO SCMI: protocol=0x%02x message=0x%02x gpio=%u action=%s\n",
           msg.protocol_id,msg.message_id,in[0],action);
    ret=devm_scmi_process_msg(base,&msg);
    /* ret!=0: lỗi transport/framework; out.status!=0: server trả lỗi.
     * Nếu ret!=0, out.status in ra không đảm bảo là phản hồi hợp lệ. */
    if(ret || out.status) {
        /* In riêng hai lớp lỗi để biết lỗi đường truyền hay lỗi xử lý lệnh. */
        printf("GPIO SCMI failed: transport=%d status=%d\n",ret,out.status);
        /* Báo lệnh thất bại cho U-Boot. */
        return CMD_RET_FAILURE;
    }
    /* %s in chuỗi. Toán tử A ? B : C chọn B khi A đúng, C khi sai.
     * GET dùng out.value vừa nhận; SET dùng in[1] đã gửi và được xác nhận.
     * Giá trị khác 0 hiện "on", bằng 0 hiện "off". */
    printf("PMU GPIO%u: %s\n",in[0],(msg.message_id==4 ? out.value : in[1]) ? "on" : "off");
    /* Message xử lý thành công và đã in trạng thái GPIO. */
    return CMD_RET_SUCCESS;
}
/* Đăng ký pmu_gpio: tối đa 3 đối số tính cả tên, không tự lặp bằng Enter;
 * gọi do_pmu_gpio; chuỗi cuối hiện các lựa chọn on|off|get trong help. */
U_BOOT_CMD(pmu_gpio,3,0,do_pmu_gpio,"control LED6 and DATA1 outputs using Ibex SCMI", "[0..4] on|off|get\nGPIO0=LED6; GPIO1..4=DATA1 pins 5..8");

/* Standard SCMI Clock protocol, clock ID 0: LED6 red blink clock.
 * The same SCMI channel carries GPIO and Clock messages. */
static int do_pmu_clock(struct cmd_tbl *cmdtp, int flag, int argc,
                         char *const argv[])
{
    struct udevice *agent, *base;
    u32 in[4]={0};
    u32 out[6]={0};
    struct scmi_msg msg={.protocol_id=SCMI_PROTOCOL_ID_CLOCK,
        .in_msg=(u8 *)in, .out_msg=(u8 *)out, .in_msg_sz=4};
    int ret;

    if(argc!=2 && argc!=3) return CMD_RET_USAGE;
    if(!strcmp(argv[1],"set")) {
        const char *p;
        u32 rate=0;

        if(argc!=3 || !argv[2][0]) return CMD_RET_USAGE;
        for(p=argv[2]; *p; p++) {
            if(*p<'0' || *p>'9') return CMD_RET_USAGE;
            rate=rate*10+(*p-'0');
            if(rate>100) return CMD_RET_USAGE;
        }
        if(rate<1) return CMD_RET_USAGE;
        msg.message_id=SCMI_CLOCK_RATE_SET;
        in[0]=0; in[1]=0; in[2]=rate; in[3]=0;
        msg.in_msg_sz=16; msg.out_msg_sz=4;
    } else if(argc!=2) return CMD_RET_USAGE;
    else if(!strcmp(argv[1],"on") || !strcmp(argv[1],"off")) {
        msg.message_id=SCMI_CLOCK_CONFIG_SET;
        in[1]=!strcmp(argv[1],"on");
        msg.in_msg_sz=8; msg.out_msg_sz=4;
    } else if(!strcmp(argv[1],"get")) {
        msg.message_id=SCMI_CLOCK_ATTRIBUTES;
        msg.out_msg_sz=sizeof(out);
    } else if(!strcmp(argv[1],"rate")) {
        msg.message_id=SCMI_CLOCK_RATE_GET;
        msg.out_msg_sz=12;
    } else return CMD_RET_USAGE;
    ret=ibex_init_agent(&agent);
    if(ret) { printf("SCMI agent unavailable (%d)\n",ret); return CMD_RET_FAILURE; }
    base=scmi_get_protocol(agent,SCMI_PROTOCOL_ID_BASE);
    if(!base) return CMD_RET_FAILURE;
    printf("PMU CLOCK SCMI: protocol=0x%02x message=0x%02x clock=0 action=%s\n",
           msg.protocol_id,msg.message_id,argv[1]);
    ret=devm_scmi_process_msg(base,&msg);
    if(ret || (s32)out[0]) {
        printf("Clock SCMI failed: transport=%d status=%d\n",ret,(s32)out[0]);
        return CMD_RET_FAILURE;
    }
    if(msg.message_id==SCMI_CLOCK_RATE_GET)
        printf("PMU clock0 led6_red rate: %llu Hz\n",((unsigned long long)out[2]<<32)|out[1]);
    else if(msg.message_id==SCMI_CLOCK_RATE_SET)
        printf("PMU clock0 led6_red rate set: %u Hz\n",in[2]);
    else
        printf("PMU clock0 led6_red: %s (red LED %s)\n",
            (msg.message_id==SCMI_CLOCK_ATTRIBUTES ? out[1]&1 : in[1]) ? "on" : "off",
            (msg.message_id==SCMI_CLOCK_ATTRIBUTES ? out[1]&1 : in[1]) ? "blinking" : "off");
    return CMD_RET_SUCCESS;
}
U_BOOT_CMD(pmu_clock,3,0,do_pmu_clock,"control LED6 red using SCMI Clock protocol",
           "on|off|get|rate|set <1..100>\nClock0=LED6 red blink, default 1 Hz; Ibex FCLK1 stays on");
