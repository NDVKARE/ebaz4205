// SPDX-License-Identifier: GPL-2.0+
#include <cyclic.h>
#include <dm.h>
#include <event.h>
#include <asm/gpio.h>
#include <asm/io.h>
#include <asm/arch/hardware.h>
#include <asm/arch/sys_proto.h>
#include <stdio.h>
#include "s2-reset-state.h"

static struct gpio_desc s2_gpio;
static struct cyclic_info s2_cyclic;
static struct s2_reset_state s2_state;

static void s2_poll(struct cyclic_info *cyclic)
{
    int pressed = dm_gpio_get_value(&s2_gpio); /* S2 is active-high in DT. */

    if (pressed < 0) {
        s2_state.pressed_samples = 0;
        s2_state.released_samples = 0;
        return;
    }
    if (!s2_reset_step(&s2_state, pressed))
        return;
    printf("\nS2: rebooting Zynq via BootROM (FSBL -> PL -> U-Boot)\n");
    /* Same Zynq system-reset helper used by U-Boot reset. Also clears
     * reboot-status bits so FSBL reloads the PL bitstream after soft reset. */
    zynq_slcr_cpu_reset();
}

static int s2_reset_init(void)
{
    ofnode node = ofnode_path("/s2-reset");
    int ret;

    if (!ofnode_valid(node)) {
        printf("S2 reset disabled: missing /s2-reset node\n");
        return 0;
    }
    /* Zynq-7000 U-Boot has no pinctrl driver for the DTS mux entries.
     * MIO20: GPIO mux, input/tristate, slow LVCMOS33, internal pull-up off.
     * S2 connects VCC when pressed; external R2645 pulls the input down.
     * Touch only this button pin; UART/SD and PS-PL clocks stay as configured. */
    zynq_slcr_unlock();
    clrsetbits_le32(&slcr_base->mio_pin[20], 0x3fff, 0x0601);
    zynq_slcr_lock();
    ret = gpio_request_by_name_nodev(node, "gpios", 0, &s2_gpio, GPIOD_IS_IN);
    if (ret) {
        printf("S2 reset disabled: GPIO request failed (%d)\n", ret);
        return 0;
    }
    cyclic_register(&s2_cyclic, s2_poll, 10000, "s2-reset");
    printf("S2 reset ready: MIO20, release then press to reboot\n");
    return 0;
}
EVENT_SPY_SIMPLE(EVT_LAST_STAGE_INIT, s2_reset_init);
