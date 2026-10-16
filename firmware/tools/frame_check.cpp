#include <cstdio>

#include "../include/frame.h"

int main() {
    stg::Frame frame{};
    frame.version = stg::kVersion;
    frame.flags = stg::kFlagBrigadista;
    frame.kind = 0;
    frame.ttl = 3;
    frame.node_id = 900;
    frame.seq = 7;
    frame.node_time = 1700000000;
    frame.lat_e6 = 20139000;
    frame.lon_e6 = -101176000;
    frame.severity = 9;
    frame.affected = 4;

    uint8_t buffer[stg::kFrameSize];
    stg::encode(frame, buffer);
    for (size_t i = 0; i < stg::kFrameSize; ++i) {
        std::printf("%02x", buffer[i]);
    }
    std::printf("\n");

    stg::Frame decoded{};
    if (!stg::decode(buffer, stg::kFrameSize, decoded)) return 1;
    if (decoded.lat_e6 != frame.lat_e6 || decoded.lon_e6 != frame.lon_e6) return 2;
    buffer[10] ^= 0xFF;
    if (stg::decode(buffer, stg::kFrameSize, decoded)) return 3;
    return 0;
}
