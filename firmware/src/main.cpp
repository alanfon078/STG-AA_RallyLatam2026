#include <Arduino.h>

#include "config.h"
#include "frame.h"
#include "radio_link.h"

#if defined(ROLE_NODE)
#include "portal.h"
#elif defined(ROLE_PORTABLE)
#include "ble_bridge.h"
#endif

namespace {

constexpr size_t kSeenCapacity = 64;
constexpr uint32_t kRelayBackoffMinMs = 50;
constexpr uint32_t kRelayBackoffMaxMs = 400;

uint32_t seenKeys[kSeenCapacity];
size_t seenCount = 0;
size_t seenNext = 0;

uint32_t keyOf(const stg::Frame& frame) {
    return (static_cast<uint32_t>(frame.node_id) << 16) | frame.seq;
}

bool markSeen(const stg::Frame& frame) {
    uint32_t key = keyOf(frame);
    for (size_t i = 0; i < seenCount; ++i) {
        if (seenKeys[i] == key) return true;
    }
    seenKeys[seenNext] = key;
    seenNext = (seenNext + 1) % kSeenCapacity;
    if (seenCount < kSeenCapacity) ++seenCount;
    return false;
}

#if defined(ROLE_GATEWAY)
void printFrame(const stg::Frame& frame) {
    uint8_t buffer[stg::kFrameSize];
    stg::encode(frame, buffer);
    Serial.print("FRAME ");
    for (size_t i = 0; i < stg::kFrameSize; ++i) {
        Serial.printf("%02x", buffer[i]);
    }
    Serial.println();
}
#endif

#if defined(ROLE_NODE) || defined(ROLE_PORTABLE)
void relay(stg::Frame frame) {
    if (frame.ttl == 0) return;
    --frame.ttl;
    delay(random(kRelayBackoffMinMs, kRelayBackoffMaxMs));
    stg::radio::send(frame);
}
#endif

}  // namespace

void setup() {
    Serial.begin(115200);
    delay(200);

    if (!stg::radio::begin()) {
        Serial.println("ERROR radio");
        while (true) delay(1000);
    }

#if defined(ROLE_NODE)
    stg::portal::begin();
    Serial.println("OK nodo");
#elif defined(ROLE_PORTABLE)
    stg::ble_bridge::begin();
    Serial.println("OK portable BLE");
#else
    Serial.println("OK gateway");
#endif
}

void loop() {
    stg::Frame incoming;
    if (stg::radio::poll(incoming) && !markSeen(incoming)) {
#if defined(ROLE_GATEWAY)
        printFrame(incoming);
#elif defined(ROLE_PORTABLE)
        stg::ble_bridge::notifyDownlink(incoming);
        relay(incoming);
#else
        relay(incoming);
#endif
    }

#if defined(ROLE_NODE)
    stg::portal::loop();
    stg::Frame outgoing;
    while (stg::portal::takePending(outgoing)) {
        markSeen(outgoing);
        stg::radio::send(outgoing);
    }
#elif defined(ROLE_PORTABLE)
    stg::Frame outgoing;
    while (stg::ble_bridge::takePending(outgoing)) {
        markSeen(outgoing);
        if (stg::radio::send(outgoing)) {
            stg::ble_bridge::notifyAck(outgoing);
        }
    }
#endif
}

