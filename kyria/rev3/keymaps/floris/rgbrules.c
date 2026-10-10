#include QMK_KEYBOARD_H
#include "host_lighting.h"

bool rgb_matrix_indicators_advanced_user(uint8_t led_min, uint8_t led_max) {
    // The host owns all colors and brightness; an expired lease leaves LEDs dark.
    if (!host_lighting_render(led_min, led_max)) {
        for (uint8_t led = led_min; led < led_max; led++) {
            rgb_matrix_set_color(led, 0, 0, 0);
        }
    }
    return false;
}
