/* SPDX-License-Identifier: GPL-2.0-or-later */
#include QMK_KEYBOARD_H

char chordal_hold_handedness(keypos_t key) {
    // Kyria matrix rows 0..3 are left; 4..7 are right. Thumb chords may
    // use either hand, so thumb modifiers/layer-taps still work one-handed.
    if (key.row % (MATRIX_ROWS / 2) == 3 && key.col != 3) {
        return '*';
    }
    return key.row < MATRIX_ROWS / 2 ? 'L' : 'R';
}
