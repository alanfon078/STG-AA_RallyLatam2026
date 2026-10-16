#pragma once

#include "frame.h"

namespace stg {
namespace radio {

bool begin();
bool send(const Frame& frame);
bool poll(Frame& out);

}  // namespace radio
}  // namespace stg
