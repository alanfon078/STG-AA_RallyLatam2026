#pragma once

#include <stdint.h>

#ifndef NODE_ID
#define NODE_ID 1
#endif

#ifndef NODE_LAT_E6
#define NODE_LAT_E6 0
#endif

#ifndef NODE_LON_E6
#define NODE_LON_E6 0
#endif

namespace stg {

namespace pin {
constexpr int kNss = 8;
constexpr int kDio1 = 14;
constexpr int kRst = 12;
constexpr int kBusy = 13;
constexpr int kSck = 9;
constexpr int kMosi = 10;
constexpr int kMiso = 11;
}  // namespace pin

namespace lora {
constexpr float kFrequencyMhz = 915.0f;
constexpr float kBandwidthKhz = 125.0f;
constexpr uint8_t kSpreadingFactor = 9;
constexpr uint8_t kCodingRate = 7;
constexpr uint8_t kSyncWord = 0x12;
constexpr int8_t kTxPowerDbm = 14;
constexpr uint16_t kPreambleLength = 8;
constexpr float kTcxoVolts = 1.8f;
}  // namespace lora

constexpr uint8_t kDefaultTtl = 3;
constexpr const char* kApSsid = "SOS_MUNICIPIO";

}  // namespace stg
