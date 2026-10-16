#include "radio_link.h"

#include <Arduino.h>
#include <RadioLib.h>
#include <SPI.h>

#include "config.h"

namespace {

SX1262 radio = new Module(stg::pin::kNss, stg::pin::kDio1, stg::pin::kRst, stg::pin::kBusy);
volatile bool packetReceived = false;

void IRAM_ATTR onPacket() {
    packetReceived = true;
}

}  // namespace

namespace stg {
namespace radio {

bool begin() {
    SPI.begin(pin::kSck, pin::kMiso, pin::kMosi, pin::kNss);
    int state = ::radio.begin(lora::kFrequencyMhz, lora::kBandwidthKhz, lora::kSpreadingFactor,
                              lora::kCodingRate, lora::kSyncWord, lora::kTxPowerDbm,
                              lora::kPreambleLength, lora::kTcxoVolts);
    if (state != RADIOLIB_ERR_NONE) return false;
    ::radio.setDio2AsRfSwitch(true);
    ::radio.setPacketReceivedAction(onPacket);
    return ::radio.startReceive() == RADIOLIB_ERR_NONE;
}

bool send(const Frame& frame) {
    uint8_t buffer[kFrameSize];
    encode(frame, buffer);
    int state = ::radio.transmit(buffer, kFrameSize);
    packetReceived = false;
    ::radio.startReceive();
    return state == RADIOLIB_ERR_NONE;
}

bool poll(Frame& out) {
    if (!packetReceived) return false;
    packetReceived = false;
    uint8_t buffer[kFrameSize + 8];
    size_t length = ::radio.getPacketLength();
    if (length > sizeof(buffer)) length = sizeof(buffer);
    int state = ::radio.readData(buffer, length);
    ::radio.startReceive();
    if (state != RADIOLIB_ERR_NONE) return false;
    return decode(buffer, length, out);
}

}  // namespace radio
}  // namespace stg
