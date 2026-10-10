#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "qmk.h"
#include "transactions.h"

static uint32_t now;
uint32_t layer_state = 4;
uint32_t default_layer_state = 1;
static uint8_t rendered[RGB_MATRIX_LED_COUNT][3];
static uint8_t sent[20][28];
static uint8_t sent_count;
static bool transport_ok = true;
static bool matrix_enabled;

uint32_t timer_read32(void) { return now; }
uint32_t timer_elapsed32(uint32_t start) { return now - start; }
uint8_t get_highest_layer(uint32_t state) {
    uint8_t highest = 0;
    while (state >>= 1) { highest++; }
    return highest;
}
bool is_keyboard_master(void) { return true; }
uint8_t rgb_matrix_get_val(void) { return 128; }
void rgb_matrix_enable_noeeprom(void) { matrix_enabled = true; }
void rgb_matrix_mode_noeeprom(uint8_t mode) { assert(mode == RGB_MATRIX_SOLID_COLOR); }
void rgb_matrix_set_color(int led, uint8_t red, uint8_t green, uint8_t blue) {
    rendered[led][0] = red;
    rendered[led][1] = green;
    rendered[led][2] = blue;
}
void transaction_register_rpc(int8_t id, slave_callback_t callback) {
    assert(id == KYRIA_HOST_LIGHTING);
    assert(callback != NULL);
}
bool transaction_rpc_send(int8_t id, uint8_t size, const void *data) {
    assert(id == KYRIA_HOST_LIGHTING && size == 28);
    assert(sent_count < 20);
    memcpy(sent[sent_count++], data, 28);
    return transport_ok;
}

#include "../../rev3/keymaps/floris/host_lighting.c"
#include "../../rev3/keymaps/floris/rgbrules.c"

static uint8_t request(uint8_t op) {
    uint8_t data[32] = {HOST_COMMAND, op};
    raw_hid_receive_kb(data, sizeof(data));
    return data[29];
}

int main(void) {
    keyboard_post_init_user();
    uint8_t status[32] = {HOST_COMMAND, HOST_STATUS};
    status[30] = 99;
    raw_hid_receive_kb(status, sizeof(status));
    assert(status[2] == 2 && status[4] == 2 && status[3] == RGB_MATRIX_LED_COUNT && status[30] == 99);
    assert(memcmp(status + 16, "KYR1", 4) == 0);
    assert(request(HOST_COMMIT) == 3); // Partial frames never become visible.
    assert(!host_lighting_render(0, RGB_MATRIX_LED_COUNT));
    uint8_t bad[32] = {HOST_COMMAND, HOST_DATA, RGB_MATRIX_LED_COUNT - 1, 2};
    raw_hid_receive_kb(bad, sizeof(bad));
    assert(bad[29] == 2);
    assert(request(HOST_BEGIN) == 0);
    for (uint8_t led = 0; led < RGB_MATRIX_LED_COUNT; led++) {
        uint8_t packet[32] = {HOST_COMMAND, HOST_DATA, led, 1, 255, 0, led};
        raw_hid_receive_kb(packet, sizeof(packet));
        assert(packet[29] == 0);
    }
    assert(request(HOST_COMMIT) == 0);
    assert(matrix_enabled);
    assert(host_lighting_render(0, RGB_MATRIX_LED_COUNT));
    assert(rendered[RGB_MATRIX_LED_COUNT - 1][0] == 255 && rendered[RGB_MATRIX_LED_COUNT - 1][2] == RGB_MATRIX_LED_COUNT - 1);
    for (uint8_t i = 0; i < 9; i++) {
        now += 5;
        housekeeping_task_user();
    }
    assert(sent_count == 9 && sent[0][1] == HOST_BEGIN && sent[8][1] == HOST_COMMIT);
    assert(sent[7][2] == 48 && sent[7][3] == 8);
    now = 1499;
    assert(request(HOST_HEARTBEAT) == 0);
    now = 2998;
    assert(host_lighting_render(25, RGB_MATRIX_LED_COUNT));
    now = 2999;
    assert(!host_lighting_render(25, RGB_MATRIX_LED_COUNT));
    assert(request(HOST_HEARTBEAT) == 4);
    housekeeping_task_user();
    assert(sent[sent_count - 1][1] == HOST_RELEASE);
    assert(request(HOST_COMMIT) == 0);
    transport_ok = false;
    now += 5;
    housekeeping_task_user();
    transport_ok = true;
    now += 5;
    housekeeping_task_user();
    assert(sent[sent_count - 1][1] == HOST_BEGIN);
    assert(request(HOST_RELEASE) == 0);
    assert(!host_lighting_render(0, RGB_MATRIX_LED_COUNT));
    rgb_matrix_indicators_advanced_user(0, RGB_MATRIX_LED_COUNT);
    for (uint8_t led = 0; led < RGB_MATRIX_LED_COUNT; led++) {
        assert(rendered[led][0] == 0 && rendered[led][1] == 0 && rendered[led][2] == 0);
    }
    puts("Firmware protocol, split framing, absolute host brightness, and timeout tests passed.");
}
