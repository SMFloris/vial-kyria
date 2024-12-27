
#include QMK_KEYBOARD_H

bool rgb_matrix_indicators_advanced_user(uint8_t led_min, uint8_t led_max) {

    switch(get_highest_layer(layer_state|default_layer_state)) {
            // numbers
            case 1:
            // i3
            case 2:
                // left number row
                rgb_matrix_set_color(13, 146, 220, 229);
                rgb_matrix_set_color(14, 175, 27, 63);
                rgb_matrix_set_color(15, 234, 214, 55);
                rgb_matrix_set_color(16, 71, 49, 68);
                rgb_matrix_set_color(17, 43, 89, 15);

                // right number row
                rgb_matrix_set_color(50, 146, 220, 229);
                rgb_matrix_set_color(51, 175, 27, 63);
                rgb_matrix_set_color(52, 234, 214, 55);
                rgb_matrix_set_color(53, 71, 49, 68);
                rgb_matrix_set_color(54, 43, 89, 15);
                break;
            case 3:
                // right number row
                rgb_matrix_set_color(51, 79, 234, 85);
                rgb_matrix_set_color(52, 57, 218, 46);
                rgb_matrix_set_color(53, 70, 228, 69);
                rgb_matrix_set_color(58, 40, 206, 15);

            default:
                break;
        }
    return false;
}
