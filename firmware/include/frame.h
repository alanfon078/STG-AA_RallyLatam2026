#pragma once

#include <stddef.h>
#include <stdint.h>

namespace stg {

constexpr uint8_t kVersion = 1;
constexpr uint8_t kFlagBrigadista = 0x01;
constexpr uint8_t kFlagPriority = 0x02;
constexpr uint8_t kMaxSeverity = 10;
constexpr uint8_t kMaxKind = 4;
constexpr size_t kFrameSize = 25;

struct Frame {
    uint8_t version;
    uint8_t flags;
    uint8_t kind;
    uint8_t ttl;
    uint16_t node_id;
    uint16_t seq;
    uint32_t node_time;
    int32_t lat_e6;
    int32_t lon_e6;
    uint8_t severity;
    uint16_t affected;
};

inline uint16_t crc16(const uint8_t* data, size_t len) {
    uint16_t crc = 0xFFFF;
    for (size_t i = 0; i < len; ++i) {
        crc ^= static_cast<uint16_t>(data[i]) << 8;
        for (int bit = 0; bit < 8; ++bit) {
            crc = (crc & 0x8000) ? static_cast<uint16_t>((crc << 1) ^ 0x1021)
                                 : static_cast<uint16_t>(crc << 1);
        }
    }
    return crc;
}

inline void putU16(uint8_t* out, uint16_t value) {
    out[0] = value & 0xFF;
    out[1] = value >> 8;
}

inline void putU32(uint8_t* out, uint32_t value) {
    for (int i = 0; i < 4; ++i) {
        out[i] = (value >> (8 * i)) & 0xFF;
    }
}

inline uint16_t getU16(const uint8_t* in) {
    return static_cast<uint16_t>(in[0] | (in[1] << 8));
}

inline uint32_t getU32(const uint8_t* in) {
    return static_cast<uint32_t>(in[0]) | (static_cast<uint32_t>(in[1]) << 8) |
           (static_cast<uint32_t>(in[2]) << 16) | (static_cast<uint32_t>(in[3]) << 24);
}

inline size_t encode(const Frame& frame, uint8_t* out) {
    out[0] = frame.version;
    out[1] = frame.flags;
    out[2] = frame.kind;
    out[3] = frame.ttl;
    putU16(out + 4, frame.node_id);
    putU16(out + 6, frame.seq);
    putU32(out + 8, frame.node_time);
    putU32(out + 12, static_cast<uint32_t>(frame.lat_e6));
    putU32(out + 16, static_cast<uint32_t>(frame.lon_e6));
    out[20] = frame.severity;
    putU16(out + 21, frame.affected);
    putU16(out + 23, crc16(out, 23));
    return kFrameSize;
}

inline bool decode(const uint8_t* in, size_t len, Frame& frame) {
    if (len != kFrameSize) return false;
    if (getU16(in + 23) != crc16(in, 23)) return false;
    if (in[0] != kVersion || in[2] > kMaxKind || in[20] > kMaxSeverity) return false;
    frame.version = in[0];
    frame.flags = in[1];
    frame.kind = in[2];
    frame.ttl = in[3];
    frame.node_id = getU16(in + 4);
    frame.seq = getU16(in + 6);
    frame.node_time = getU32(in + 8);
    frame.lat_e6 = static_cast<int32_t>(getU32(in + 12));
    frame.lon_e6 = static_cast<int32_t>(getU32(in + 16));
    frame.severity = in[20];
    frame.affected = getU16(in + 21);
    return true;
}

}  // namespace stg
