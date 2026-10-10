#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "qmk.h"
#include "transactions.h"

static uint32_t now;
uint32_t layer_state = 4;
uint32_t default_layer_state = 1;
static uint8_t rendered[62][3];
static uint8_t sent[20][28];
static uint8_t sent_count;
static bool transport_ok = true;

uint32_t timer_read32(void) { return now; }
uint32_t timer_elapsed32(uint32_t start) { return now - start; }
uint8_t get_highest_layer(uint32_t state) {
    uint8_t highest = 0;
    while (state >>= 1) { highest++; }
    return highest;
}
bool is_keyboard_master(void) { return true; }
uint8_t rgb_matrix_get_val(void) { return 128; }
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
    assert(status[4] == 2 && status[3] == 62 && status[30] == 99);
    assert(memcmp(status + 16, "KYR1", 4) == 0);
    assert(request(HOST_COMMIT) == 3); // Partial frames never become visible.
    assert(!host_lighting_render(0, 62));
    uint8_t bad[32] = {HOST_COMMAND, HOST_DATA, 61, 2};
    raw_hid_receive_kb(bad, sizeof(bad));
    assert(bad[29] == 2);
    assert(request(HOST_BEGIN) == 0);
    for (uint8_t led = 0; led < 62; led++) {
        uint8_t packet[32] = {HOST_COMMAND, HOST_DATA, led, 1, 255, 0, led};
        raw_hid_receive_kb(packet, sizeof(packet));
        assert(packet[29] == 0);
    }
    assert(request(HOST_COMMIT) == 0);
    assert(host_lighting_render(0, 62));
    assert(rendered[61][0] == 128 && rendered[61][2] == 61 * 128 / 255);
    for (uint8_t i = 0; i < 10; i++) {
        now += 5;
        housekeeping_task_user();
    }
    assert(sent_count == 10 && sent[0][1] == HOST_BEGIN && sent[9][1] == HOST_COMMIT);
    assert(sent[8][2] == 56 && sent[8][3] == 6);
    now = 1499;
    assert(request(HOST_HEARTBEAT) == 0);
    now = 2998;
    assert(host_lighting_render(31, 62));
    now = 2999;
    assert(!host_lighting_render(31, 62));
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
    assert(!host_lighting_render(0, 62));
    puts("Firmware protocol, split framing, brightness, and timeout tests passed.");
}
