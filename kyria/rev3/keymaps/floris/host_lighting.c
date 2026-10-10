/* SPDX-License-Identifier: GPL-2.0-or-later */
#include "host_lighting.h"
#include "transactions.h"
#include <string.h>

// Private raw-HID extension; VIA/Vial still handle their own commands.
#define HOST_COMMAND 0xF0
#define HOST_VERSION 1
#define HOST_TIMEOUT_MS 1500
#define FRAME_CHUNK_LEDS 8

enum host_operation {
    HOST_STATUS,
    HOST_DATA,
    HOST_COMMIT,
    HOST_RELEASE,
    HOST_HEARTBEAT,
    HOST_BEGIN,
};

_Static_assert(RGB_MATRIX_LED_COUNT <= 63, "Host frame mask supports up to 63 LEDs");

static uint8_t staged[RGB_MATRIX_LED_COUNT][3];
static uint8_t colors[RGB_MATRIX_LED_COUNT][3];
static uint64_t staged_mask;
static bool hosted;
static uint32_t last_heartbeat;
static bool sync_pending;
static uint8_t sync_phase;
static uint32_t last_sync_attempt;
static uint32_t last_slave_refresh;

static bool host_active(void) {
    return hosted && timer_elapsed32(last_heartbeat) < HOST_TIMEOUT_MS;
}

// Returns an error code; a frame only becomes visible after a complete commit.
static uint8_t apply_packet(const uint8_t *data) {
    switch (data[1]) {
        case HOST_BEGIN:
            staged_mask = 0;
            break;
        case HOST_DATA: {
            uint8_t start = data[2];
            uint8_t count = data[3];
            if (!count || count > FRAME_CHUNK_LEDS || start + count > RGB_MATRIX_LED_COUNT) {
                return 2;
            }
            memcpy(&staged[start], &data[4], count * 3);
            for (uint8_t i = start; i < start + count; i++) {
                staged_mask |= (uint64_t)1 << i;
            }
            break;
        }
        case HOST_COMMIT:
            if (staged_mask != (((uint64_t)1 << RGB_MATRIX_LED_COUNT) - 1)) {
                return 3;
            }
            memcpy(colors, staged, sizeof(colors));
            hosted = true;
            last_heartbeat = timer_read32();
            break;
        case HOST_HEARTBEAT:
            // An expired lease must be replaced by a complete new frame.
            if (!host_active()) {
                return 4;
            }
            last_heartbeat = timer_read32();
            break;
        case HOST_RELEASE:
            hosted = false;
            staged_mask = 0;
            break;
        default:
            return 1;
    }
    return 0;
}

void raw_hid_receive_kb(uint8_t *data, uint8_t length) {
    if (length != 32 || data[0] != HOST_COMMAND) {
        data[0] = 0xFF;
        return;
    }
    if (data[1] == HOST_STATUS) {
        data[2] = HOST_VERSION;
        data[3] = RGB_MATRIX_LED_COUNT;
        data[4] = get_highest_layer(layer_state | default_layer_state);
        data[5] = host_active();
        data[6] = sync_pending;
        uint32_t layers = layer_state;
        uint32_t defaults = default_layer_state;
        memcpy(&data[8], &layers, sizeof(layers));
        memcpy(&data[12], &defaults, sizeof(defaults));
        memcpy(&data[16], "KYR1", 4);
        data[29] = 0;
        return;
    }
    data[29] = apply_packet(data);
    if (!data[29] && (data[1] == HOST_COMMIT || data[1] == HOST_RELEASE)) {
        sync_pending = true;
        sync_phase = 0;
    }
}

static void slave_receive(uint8_t in_length, const void *in_data, uint8_t out_length, void *out_data) {
    (void)out_length;
    (void)out_data;
    if (in_length == 28) {
        apply_packet(in_data);
    }
}

void keyboard_post_init_user(void) {
    transaction_register_rpc(KYRIA_HOST_LIGHTING, slave_receive);
}

void housekeeping_task_user(void) {
    if (!is_keyboard_master()) {
        return;
    }
    if (hosted && !host_active()) {
        hosted = false;
        sync_pending = true;
        sync_phase = 0;
    }
    if (timer_elapsed32(last_sync_attempt) < 4) {
        return;
    }
    if (!sync_pending && (!host_active() || timer_elapsed32(last_slave_refresh) < 250)) {
        return;
    }
    last_sync_attempt = timer_read32();
    uint8_t packet[28] = {HOST_COMMAND, HOST_HEARTBEAT};
    uint8_t chunks = (RGB_MATRIX_LED_COUNT + FRAME_CHUNK_LEDS - 1) / FRAME_CHUNK_LEDS;
    if (sync_pending) {
        if (!host_active()) {
            packet[1] = HOST_RELEASE;
        } else if (sync_phase == 0) {
            packet[1] = HOST_BEGIN;
        } else if (sync_phase <= chunks) {
            packet[1] = HOST_DATA;
            packet[2] = (sync_phase - 1) * FRAME_CHUNK_LEDS;
            packet[3] = RGB_MATRIX_LED_COUNT - packet[2];
            if (packet[3] > FRAME_CHUNK_LEDS) {
                packet[3] = FRAME_CHUNK_LEDS;
            }
            memcpy(&packet[4], &colors[packet[2]], packet[3] * 3);
        } else {
            packet[1] = HOST_COMMIT;
        }
    }
    if (transaction_rpc_send(KYRIA_HOST_LIGHTING, sizeof(packet), packet)) {
        if (sync_pending && packet[1] != HOST_COMMIT && packet[1] != HOST_RELEASE) {
            sync_phase++;
        } else {
            sync_pending = false;
            last_slave_refresh = timer_read32();
        }
    } else {
        // Re-send a complete frame when the other half reconnects.
        sync_pending = true;
        sync_phase = 0;
    }
}

bool host_lighting_render(uint8_t led_min, uint8_t led_max) {
    if (!host_active()) {
        return false;
    }
    uint8_t brightness = rgb_matrix_get_val();
    for (uint8_t led = led_min; led < led_max; led++) {
        rgb_matrix_set_color(led,
            (uint16_t)colors[led][0] * brightness / 255,
            (uint16_t)colors[led][1] * brightness / 255,
            (uint16_t)colors[led][2] * brightness / 255);
    }
    return true;
}
