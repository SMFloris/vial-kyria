#pragma once
#include "qmk.h"
typedef void (*slave_callback_t)(uint8_t, const void *, uint8_t, void *);
void transaction_register_rpc(int8_t id, slave_callback_t callback);
bool transaction_rpc_send(int8_t id, uint8_t size, const void *data);
