/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Copyright 2023 splitkb.com <support@splitkb.com> */

#pragma once

#define VIAL_KEYBOARD_UID {0x0F, 0xF9, 0x13, 0x6C, 0x1D, 0xBF, 0x7D, 0xA6}

#define VIAL_UNLOCK_COMBO_ROWS { 0, 4 }
#define VIAL_UNLOCK_COMBO_COLS { 1, 1 }

#define SPLIT_LAYER_STATE_ENABLE
#define SPLIT_TRANSACTION_IDS_USER KYRIA_HOST_LIGHTING
#define RGB_MATRIX_DEFAULT_MODE RGB_MATRIX_SOLID_COLOR
#define RGB_MATRIX_DEFAULT_HUE 0
#define RGB_MATRIX_DEFAULT_SAT 0
#define RGB_MATRIX_DEFAULT_VAL 16

#define DYNAMIC_KEYMAP_LAYER_COUNT 8

// Vial compiles these features itself and reads their settings from layout.vil.
#define TAPPING_TERM 250
#ifndef QMK_SETTINGS
#define PERMISSIVE_HOLD
#define CHORDAL_HOLD
#define FLOW_TAP_TERM 150
#endif
