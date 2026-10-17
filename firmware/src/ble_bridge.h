#pragma once

#include "frame.h"

namespace stg {
namespace ble_bridge {

void begin();
bool takePending(Frame& out);
void notifyAck(const Frame& frame);
void notifyDownlink(const Frame& frame);

}  // namespace ble_bridge
}  // namespace stg
