#include QMK_KEYBOARD_H
#include "host_lighting.h"

bool rgb_matrix_indicators_advanced_user(uint8_t led_min, uint8_t led_max) {
    // Only a neutral white fallback lives in firmware; the host owns layer colors.
    if (!host_lighting_render(led_min, led_max)) {
        for (uint8_t led = led_min; led < led_max; led++) {
            rgb_matrix_set_color(led, 16, 16, 16);
        }
    }
    return false;
}
