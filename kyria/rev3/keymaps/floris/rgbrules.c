#include QMK_KEYBOARD_H
#include "host_lighting.h"

enum indicator_layers {
    NUMBER_LAYER = 1,
    COSMIC_LAYER = 2,
    NAVIGATION_LAYER = 3,
};

static void set_indicator(uint8_t led, uint8_t led_min, uint8_t led_max, uint8_t red, uint8_t green, uint8_t blue) {
    if (led >= led_min && led < led_max) {
        rgb_matrix_set_color(led, red, green, blue);
    }
}

static void set_layer_underglow(uint8_t layer, uint8_t led_min, uint8_t led_max) {
    static const uint8_t colors[8][3] = {
        {0, 90, 255},    // 0: typing - blue
        {255, 150, 0},   // 1: numbers - amber
        {180, 0, 255},   // 2: COSMIC - purple
        {0, 255, 60},    // 3: navigation - green
        {0, 255, 255},   // 4: editor macros - cyan
        {255, 0, 0},     // 5: function keys - red
        {255, 255, 255}, // 6: settings - white
        {255, 0, 120},   // 7: spare - pink
    };
    if (layer >= sizeof(colors) / sizeof(colors[0])) {
        layer = 0;
    }

    // Follow the user's brightness setting and leave key LEDs to their effects.
    uint8_t brightness = rgb_matrix_get_val();
    uint8_t red = (uint16_t)colors[layer][0] * brightness / 255;
    uint8_t green = (uint16_t)colors[layer][1] * brightness / 255;
    uint8_t blue = (uint16_t)colors[layer][2] * brightness / 255;
    for (uint8_t led = led_min; led < led_max; led++) {
        if (g_led_config.flags[led] & LED_FLAG_UNDERGLOW) {
            rgb_matrix_set_color(led, red, green, blue);
        }
    }
}

bool rgb_matrix_indicators_advanced_user(uint8_t led_min, uint8_t led_max) {
    if (host_lighting_render(led_min, led_max)) {
        return false;
    }
    uint8_t layer = get_highest_layer(layer_state | default_layer_state);
    set_layer_underglow(layer, led_min, led_max);

    if (layer == NUMBER_LAYER || layer == COSMIC_LAYER) {
        // Home-row numbers/workspaces: left 5..1, right 6..0.
        static const uint8_t colors[5][3] = {
            {146, 220, 229},
            {175, 27, 63},
            {234, 214, 55},
            {71, 49, 68},
            {43, 89, 15},
        };
        for (uint8_t i = 0; i < 5; i++) {
            set_indicator(19 + i, led_min, led_max, colors[i][0], colors[i][1], colors[i][2]);
            set_indicator(50 + i, led_min, led_max, colors[i][0], colors[i][1], colors[i][2]);
        }
    }

    if (layer == COSMIC_LAYER || layer == NAVIGATION_LAYER) {
        // COSMIC focus: N/M/Comma/Period. Navigation arrows: H/J/K/L.
        uint8_t first_led = layer == COSMIC_LAYER ? 44 : 50;
        for (uint8_t i = 0; i < 4; i++) {
            set_indicator(first_led + i, led_min, led_max, 79, 234, 85);
        }
    }

    return false;
}
