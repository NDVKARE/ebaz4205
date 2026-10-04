#ifndef IBEX_SCMI_PROTOCOLS_H
#define IBEX_SCMI_PROTOCOLS_H

/* Wire IDs shared with U-Boot's include/scmi_protocols.h.
 * This freestanding header has no dependency on U-Boot types or drivers. */
enum scmi_protocol_id {
    SCMI_PROTOCOL_ID_BASE = 0x10,
    SCMI_PROTOCOL_ID_CLOCK = 0x14,
    SCMI_PROTOCOL_ID_GPIO = 0x80, /* Project-specific vendor protocol. */
};

enum scmi_common_message_id {
    SCMI_PROTOCOL_VERSION = 0x0,
    SCMI_PROTOCOL_ATTRIBUTES = 0x1,
    SCMI_PROTOCOL_MESSAGE_ATTRIBUTES = 0x2,
};

enum scmi_base_message_id {
    SCMI_BASE_DISCOVER_VENDOR = 0x3,
    SCMI_BASE_DISCOVER_SUB_VENDOR = 0x4,
    SCMI_BASE_DISCOVER_IMPL_VERSION = 0x5,
    SCMI_BASE_DISCOVER_LIST_PROTOCOLS = 0x6,
    SCMI_BASE_DISCOVER_AGENT = 0x7,
    SCMI_BASE_NOTIFY_ERRORS = 0x8, /* Defined, but not supported by this server. */
};

enum scmi_gpio_message_id {
    SCMI_GPIO_SET = 0x3,
    SCMI_GPIO_GET = 0x4,
};

enum scmi_clock_message_id {
    SCMI_CLOCK_ATTRIBUTES = 0x3,
    SCMI_CLOCK_DESCRIBE_RATES = 0x4,
    SCMI_CLOCK_RATE_SET = 0x5,
    SCMI_CLOCK_RATE_GET = 0x6,
    SCMI_CLOCK_CONFIG_SET = 0x7,
};
#define SCMI_CLOCK_PROTOCOL_VERSION 0x00010000u
#define SCMI_CLOCK_ENABLE 1u
#define SCMI_CLOCK_LED6_ID 0u
#define SCMI_CLOCK_LED6_RATE_HZ 1u
#define IBEX_REG_LED_CLOCK 0x24u
#define IBEX_REG_LED_RATE 0x28u
#define SCMI_CLOCK_LED6_MIN_HZ 1u
#define SCMI_CLOCK_LED6_MAX_HZ 100u

enum scmi_status {
    SCMI_SUCCESS = 0,
    SCMI_NOT_SUPPORTED = -1,
    SCMI_INVALID_PARAMETERS = -2,
    SCMI_NOT_FOUND = -3,
};

#define SCMI_BASE_PROTOCOL_VERSION 0x00020000u
#define SCMI_GPIO_PROTOCOL_VERSION 0x00010000u
#define SCMI_BASE_NAME_LENGTH_MAX 16u

/* Header: message[7:0], type[9:8], protocol[17:10], token[27:18]. */
#define SCMI_HEADER_MESSAGE_ID(h) ((h) & 0xffu)
#define SCMI_HEADER_MESSAGE_TYPE(h) (((h) >> 8) & 0x3u)
#define SCMI_HEADER_PROTOCOL_ID(h) (((h) >> 10) & 0xffu)
#define SCMI_HEADER_TOKEN(h) (((h) >> 18) & 0x3ffu)
#define SCMI_MESSAGE_TYPE_COMMAND 0u

/* SMT indices are 32-bit words, not byte offsets. */
#define SCMI_SMT_CHANNEL_STATUS 1u
#define SCMI_SMT_FLAGS 4u
#define SCMI_SMT_LENGTH 5u
#define SCMI_SMT_HEADER 6u
#define SCMI_SMT_PAYLOAD 7u
#define SCMI_SHMEM_CHAN_STAT_CHANNEL_FREE 1u
#define SCMI_SMT_SIZE_BYTES 4096u
#define SCMI_SMT_METADATA_BYTES 24u
#define SCMI_HEADER_SIZE_BYTES 4u

#endif /* IBEX_SCMI_PROTOCOLS_H */
