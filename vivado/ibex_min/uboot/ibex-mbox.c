// SPDX-License-Identifier: GPL-2.0+
#include <dm.h>
#include <clk.h>
#include <mailbox-uclass.h>
#include <asm/io.h>
#include <asm/arch/hardware.h>
#include <asm/arch/sys_proto.h>
#include <linux/delay.h>
#include <linux/errno.h>
#include <linux/err.h>
struct ibex_mbox { void __iomem *regs; u32 trace_id; };
/* The SCMI transport passes its mapped SMT buffer to send/recv.
 * Dump actual words before request and after completion, not guessed values. */
static void ibex_trace_word(const char *phase, const char *name,
                            const void __iomem *addr, u32 value,
                            const char *meaning)
{
    printf("  %s %-14s [0x%08lx] = 0x%08x => %s\n",
           phase, name, (ulong)addr, value, meaning);
}
static const char *ibex_protocol_name(u32 protocol)
{
    switch (protocol) {
    case 0x10: return "Base";
    case 0x14: return "Clock";
    case 0x80: return "GPIO";
    default: return "unknown";
    }
}
static const char *ibex_message_name(u32 protocol, u32 id)
{
    if (id == 0) return "PROTOCOL_VERSION";
    if (id == 1) return "PROTOCOL_ATTRIBUTES";
    if (id == 2) return "PROTOCOL_MESSAGE_ATTRIBUTES";
    if (protocol == 0x10) {
        switch (id) {
        case 3: return "BASE_DISCOVER_VENDOR";
        case 4: return "BASE_DISCOVER_SUB_VENDOR";
        case 5: return "BASE_DISCOVER_IMPL_VERSION";
        case 6: return "BASE_DISCOVER_LIST_PROTOCOLS";
        case 7: return "BASE_DISCOVER_AGENT";
        }
    } else if (protocol == 0x14) {
        switch (id) {
        case 3: return "CLOCK_ATTRIBUTES";
        case 4: return "CLOCK_DESCRIBE_RATES";
        case 5: return "CLOCK_RATE_SET";
        case 6: return "CLOCK_RATE_GET";
        case 7: return "CLOCK_CONFIG_SET";
        }
    } else if (protocol == 0x80) {
        if (id == 3) return "GPIO_SET";
        if (id == 4) return "GPIO_GET";
    }
    return "unknown message";
}
static const char *ibex_status_name(s32 status)
{
    switch (status) {
    case 0: return "SUCCESS";
    case -1: return "NOT_SUPPORTED";
    case -2: return "INVALID_PARAMETERS";
    case -3: return "NOT_FOUND";
    case -4: return "DENIED";
    case -5: return "OUT_OF_RANGE";
    case -6: return "BUSY";
    case -7: return "COMMS_ERROR";
    case -8: return "GENERIC_ERROR";
    case -9: return "HARDWARE_ERROR";
    case -10: return "PROTOCOL_ERROR";
    default: return "unknown status";
    }
}
static const char *ibex_payload_meaning(bool rx, u32 protocol, u32 id, u32 index)
{
    if (!rx) {
        if (id == 2 && index == 0) return "message ID being queried";
        if (protocol == 0x10 && id == 6 && index == 0)
            return "number of protocol IDs to skip";
        if (protocol == 0x10 && id == 7 && index == 0)
            return "agent ID (0xffffffff = calling agent)";
        if (protocol == 0x80 && (id == 3 || id == 4)) {
            if (index == 0) return "GPIO ID (0=LED6 green, 1..4=DATA1)";
            if (id == 3 && index == 1) return "GPIO value (0=off, 1=on)";
        }
        if (protocol == 0x14 && id >= 3) {
            if (id == 5) {
                if (index == 0) return "rate-set flags (0=synchronous, exact rate)";
                if (index == 1) return "clock ID (0=LED6 red blink clock)";
                if (index == 2) return "requested rate in Hz, low 32 bits (1..100)";
                if (index == 3) return "requested rate in Hz, high 32 bits (must be 0)";
            }
            if (index == 0) return "clock ID (0=LED6 red blink clock)";
            if (id == 7 && index == 1) return "clock attributes: bit0 enable (0=off, 1=on)";
            if (id == 4 && index == 1) return "rate index";
        }
        return "request data word";
    }
    /* RX index zero is status; only decode remaining words after success. */
    if (id == 0 && index == 1) return "protocol version: major[31:16], minor[15:0]";
    if (id == 1 && index == 1) {
        if (protocol == 0x10) return "attributes: agents[15:8], protocols[7:0]";
        if (protocol == 0x80) return "number of GPIO outputs";
        if (protocol == 0x14) return "attributes: clock count[15:0]";
    }
    if (id == 2 && index == 1) return "message attributes (0=no extra flags)";
    if (protocol == 0x10) {
        if (id == 3 || id == 4 || (id == 7 && index >= 2))
            return "name bytes (little-endian, 16-byte field)";
        if (id == 5 && index == 1) return "implementation version";
        if (id == 6 && index == 1) return "number of returned protocol IDs";
        if (id == 6 && index >= 2) return "packed protocol IDs, low byte first (0x14=Clock, 0x80=GPIO)";
        if (id == 7 && index == 1) return "resolved agent ID";
    }
    if (protocol == 0x80 && id == 4 && index == 1)
        return "GPIO value (0=off, 1=on)";
    if (protocol == 0x14) {
        if (id == 3 && index == 1) return "clock attributes: bit0 enabled";
        if (id == 3 && index >= 2) return "clock name bytes (little-endian)";
        if (id == 4 && index == 1) return "rate flags: count[11:0], bit12 format (0=discrete, 1=range), remaining[31:16]";
        if (id == 4 && index == 2) return "minimum rate in Hz, low 32 bits";
        if (id == 4 && index == 3) return "minimum rate in Hz, high 32 bits";
        if (id == 4 && index == 4) return "maximum rate in Hz, low 32 bits";
        if (id == 4 && index == 5) return "maximum rate in Hz, high 32 bits";
        if (id == 4 && index == 6) return "rate step in Hz, low 32 bits";
        if (id == 4 && index == 7) return "rate step in Hz, high 32 bits";
        if ((id == 4 && index == 2) || (id == 6 && index == 1)) return "rate in Hz, low 32 bits";
        if ((id == 4 && index == 3) || (id == 6 && index == 2)) return "rate in Hz, high 32 bits";
    }
    return "response data word";
}
static void ibex_trace_smt(const char *phase, const void *data)
{
    const u8 __iomem *shm = data;
    u32 length, offset, header, protocol, id, value, index;
    bool rx = phase[0] == 'R';
    char meaning[120], label[24];

    if (!shm) return;
    length = readl(shm + 0x14);
    header = readl(shm + 0x18);
    protocol = (header >> 10) & 0xff;
    id = header & 0xff;
    value = readl(shm + 4);
    snprintf(meaning, sizeof(meaning), "channel %s; error=%u",
             value & 1 ? "free" : "busy", (value >> 1) & 1);
    ibex_trace_word(phase, "channel_status", shm + 4, value, meaning);
    ibex_trace_word(phase, "flags", shm + 0x10, readl(shm + 0x10),
                    "bit0 requests interrupt response; this server uses polling");
    snprintf(meaning, sizeof(meaning), "%u bytes = header + payload", length);
    ibex_trace_word(phase, "length", shm + 0x14, length, meaning);
    snprintf(meaning, sizeof(meaning), "%s(0x%02x), %s(0x%02x), type=%u, token=%u",
             ibex_protocol_name(protocol), protocol, ibex_message_name(protocol, id),
             id, (header >> 8) & 3, (header >> 18) & 0x3ff);
    ibex_trace_word(phase, "header", shm + 0x18, header, meaning);
    /* Length includes header, excludes SMT metadata. The buffer is 4 KiB. */
    if (length < 4 || length > 0x1000 - 0x18 || (length & 3)) {
        printf("  %s => invalid length; skipping payload\n", phase);
        return;
    }
    for (offset = 4; offset < length; offset += 4) {
        index = (offset - 4) / 4;
        value = readl(shm + 0x18 + offset);
        snprintf(label, sizeof(label), "payload[%u]", index);
        if (rx && index == 0) {
            snprintf(meaning, sizeof(meaning), "status=%d (%s)",
                     (s32)value, ibex_status_name((s32)value));
            ibex_trace_word(phase, label, shm + 0x18 + offset, value, meaning);
        } else {
            const char *decoded = rx && readl(shm + 0x1c) != 0 ?
                "data after error status; not decoded" :
                ibex_payload_meaning(rx, protocol, id, index);
            ibex_trace_word(phase, label, shm + 0x18 + offset, value, decoded);
        }
    }
}
static int ibex_request(struct mbox_chan *chan) { return chan->id ? -EINVAL : 0; }
static int ibex_free(struct mbox_chan *chan) { return 0; }
static int ibex_send(struct mbox_chan *chan, const void *data)
{
    struct ibex_mbox *p = dev_get_priv(chan->dev);
    if (readl(p->regs + 8) != 0x49424558) return -ENODEV;
    if (readl(p->regs) & 1) return -EBUSY;
    printf("\n========== SCMI TX #%u: U-Boot -> Ibex ==========\n", ++p->trace_id);
    ibex_trace_smt("TX", data);
    writel(0, p->regs + 4);
    ibex_trace_word("TX", "completion", p->regs + 4, 0, "clear previous completion");
    mb();
    writel(1, p->regs);
    ibex_trace_word("TX", "request", p->regs, 1, "ring doorbell; request Ibex processing");
    printf("================ END TX #%u ================\n\n", p->trace_id);
    return 0;
}
static int ibex_recv(struct mbox_chan *chan, void *data)
{
    struct ibex_mbox *p = dev_get_priv(chan->dev);
    if (!(readl(p->regs + 4) & 1)) return -ENODATA;
    mb();
    printf("\n========== SCMI RX #%u: Ibex -> U-Boot ==========\n", p->trace_id);
    ibex_trace_word("RX", "completion", p->regs + 4, readl(p->regs + 4), "Ibex response ready");
    ibex_trace_smt("RX", data);
    ibex_trace_word("RX", "gpio_bitmap", p->regs + 0x10,
                    readl(p->regs + 0x10), "GPIO state bitmap, bits 0..4");
    ibex_trace_word("RX", "led_clock", p->regs + 0x24,
                    readl(p->regs + 0x24), "LED6 red blink clock enable (0=off, 1=on)");
    ibex_trace_word("RX", "led_rate_hz", p->regs + 0x28,
                    readl(p->regs + 0x28), "LED6 red blink rate in Hz (1..100)");
    writel(0, p->regs + 4);
    ibex_trace_word("RX", "completion ACK", p->regs + 4, 0, "U-Boot acknowledges response");
    printf("================ END RX #%u ================\n\n", p->trace_id);
    return 0;
}
static int ibex_probe(struct udevice *dev)
{
    struct ibex_mbox *p = dev_get_priv(dev);
    struct clk clock;
    ulong rate;
    int ret, i;
    /* Ibex starts with the system. FSBL owns PL clock/reset initialization.
     * Attaching the mailbox must not reset an already running firmware. */
    if (!(readl(&devcfg_base->int_sts) & BIT(2))) return -ENODEV;
    printf("Ibex: PL configured; checking FCLK1\n");
    p->regs = dev_read_addr_ptr(dev);
    if (!p->regs) return -EINVAL;
    ret = clk_get_by_index(dev, 0, &clock);
    if (ret) return ret;
    rate = clk_get_rate(&clock);
    if (IS_ERR_VALUE(rate)) return (int)rate;
    if (rate < 24900000 || rate > 25100000) return -ERANGE;
    printf("Ibex: FCLK1=%lu Hz\n", rate);
    if (readl(&slcr_base->fpga_rst_ctrl) & BIT(1)) {
        printf("Ibex: FCLK1 reset still asserted; check FSBL initialization\n");
        return -ENODEV;
    }
    printf("Ibex: attaching to running firmware; reading AXI ready\n");
    for (i = 0; i < 1000; i++) {
        if (readl(p->regs + 8) == 0x49424558) {
            printf("Ibex: firmware ready\n");
            return 0;
        }
        udelay(100);
    }
    return -ETIMEDOUT;
}
static const struct udevice_id ibex_ids[] = {{.compatible="ebaz4205,ibex-mailbox"}, {}};
static const struct mbox_ops ibex_ops = {
    .request=ibex_request, .rfree=ibex_free, .send=ibex_send, .recv=ibex_recv
};
U_BOOT_DRIVER(ibex_mbox) = {
    .name="ibex_mbox", .id=UCLASS_MAILBOX, .of_match=ibex_ids,
    .probe=ibex_probe, .priv_auto=sizeof(struct ibex_mbox), .ops=&ibex_ops
};
