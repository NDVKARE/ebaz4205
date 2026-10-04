#include <assert.h>
#include <stdio.h>
#include "../uboot/s2-reset-state.h"

int main(void)
{
    struct s2_reset_state state = {0};
    unsigned int i;
    /* Held at startup: must never reset until a stable release is seen. */
    for (i = 0; i < 100; i++) assert(!s2_reset_step(&state, 1));
    /* A short release bounce must not arm the button. */
    for (i = 0; i < 3; i++) assert(!s2_reset_step(&state, 0));
    for (i = 0; i < 10; i++) assert(!s2_reset_step(&state, 1));
    for (i = 0; i < S2_DEBOUNCE_SAMPLES; i++) assert(!s2_reset_step(&state, 0));
    /* A short press bounce followed by release must not trigger. */
    for (i = 0; i < 3; i++) assert(!s2_reset_step(&state, 1));
    assert(!s2_reset_step(&state, 0));
    for (i = 0; i < S2_DEBOUNCE_SAMPLES - 1; i++) assert(!s2_reset_step(&state, 1));
    assert(s2_reset_step(&state, 1));
    /* Continuing to hold generates no repeat reset, even if reset fails. */
    for (i = 0; i < 100; i++) assert(!s2_reset_step(&state, 1));
    for (i = 0; i < S2_DEBOUNCE_SAMPLES; i++) assert(!s2_reset_step(&state, 0));
    for (i = 0; i < S2_DEBOUNCE_SAMPLES - 1; i++) assert(!s2_reset_step(&state, 1));
    assert(s2_reset_step(&state, 1));
    puts("PASS: held-at-boot, release/press debounce, bounce rejection, no repeats, re-arm");
    return 0;
}
