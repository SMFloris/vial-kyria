#pragma once
#include <stdbool.h>
#include <stdint.h>
#define RGB_MATRIX_LED_COUNT 56
#define RGB_MATRIX_SOLID_COLOR 1
#define KYRIA_HOST_LIGHTING 42
#define MATRIX_ROWS 8
typedef struct { uint8_t col, row; } keypos_t;
extern uint32_t layer_state;
extern uint32_t default_layer_state;
uint32_t timer_read32(void);
uint32_t timer_elapsed32(uint32_t start);
uint8_t get_highest_layer(uint32_t state);
bool is_keyboard_master(void);
uint8_t rgb_matrix_get_val(void);
void rgb_matrix_enable_noeeprom(void);
void rgb_matrix_mode_noeeprom(uint8_t mode);
void rgb_matrix_sethsv_noeeprom(uint8_t hue, uint8_t saturation, uint8_t value);
void rgb_matrix_set_color(int led, uint8_t red, uint8_t green, uint8_t blue);
