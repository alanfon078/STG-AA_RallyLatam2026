#pragma once

#include "frame.h"

namespace stg {
namespace portal {

void begin();
void loop();
bool takePending(Frame& out);

}  // namespace portal
}  // namespace stg
