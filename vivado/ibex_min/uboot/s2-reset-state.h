#ifndef EBAZ_S2_RESET_STATE_H
#define EBAZ_S2_RESET_STATE_H

#define S2_DEBOUNCE_SAMPLES 6u /* 10 ms sampling: >=50 ms stable level. */
struct s2_reset_state {
    unsigned int released_samples;
    unsigned int pressed_samples;
    int armed;
};

/* Require stable release before each stable press, including at startup. */
static inline int s2_reset_step(struct s2_reset_state *state, int pressed)
{
    if (!pressed) {
        state->pressed_samples = 0;
        if (state->released_samples < S2_DEBOUNCE_SAMPLES)
            state->released_samples++;
        if (state->released_samples == S2_DEBOUNCE_SAMPLES)
            state->armed = 1;
        return 0;
    }
    state->released_samples = 0;
    if (!state->armed) {
        state->pressed_samples = 0;
        return 0;
    }
    if (++state->pressed_samples < S2_DEBOUNCE_SAMPLES)
        return 0;
    state->armed = 0;
    state->pressed_samples = 0;
    return 1;
}
#endif
