#if defined(ROLE_PORTABLE)

#include "ble_bridge.h"

#include <Arduino.h>
#include <BLE2902.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <WiFi.h>
#include <cstdio>
#include <string>

#include "config.h"

namespace {

constexpr size_t kBleQueueDepth = 12;

QueueHandle_t blePendingQueue = nullptr;
BLEServer* bleServer = nullptr;
BLECharacteristic* txChar = nullptr;
volatile bool clientConnected = false;

class ServerCallbacks : public BLEServerCallbacks {
    void onConnect(BLEServer* server) override {
        (void)server;
        clientConnected = true;
    }

    void onDisconnect(BLEServer* server) override {
        clientConnected = false;
        server->startAdvertising();
    }
};

class RxCallbacks : public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic* characteristic) override {
        std::string raw = characteristic->getValue();
        if (raw.size() != stg::kFrameSize) return;

        stg::Frame frame{};
        if (!stg::decode(reinterpret_cast<const uint8_t*>(raw.data()), raw.size(), frame)) {
            return;
        }
        frame.flags |= stg::kFlagBrigadista;
        if (frame.node_id == 0) {
            frame.node_id = NODE_ID;
        }
        if (blePendingQueue != nullptr) {
            xQueueSend(blePendingQueue, &frame, 0);
        }
    }
};

}  // namespace

namespace stg {
namespace ble_bridge {

void begin() {
    // Apagar Wi-Fi por completo en el nodo portátil para cumplir presupuesto < 0.5 W
    WiFi.mode(WIFI_OFF);
    WiFi.disconnect(true, true);

    blePendingQueue = xQueueCreate(kBleQueueDepth, sizeof(Frame));

    char devName[32];
    std::snprintf(devName, sizeof(devName), "%s%u", ble::kDeviceNamePrefix,
                  static_cast<unsigned>(NODE_ID));

    BLEDevice::init(devName);
    bleServer = BLEDevice::createServer();
    bleServer->setCallbacks(new ServerCallbacks());

    BLEService* service = bleServer->createService(ble::kServiceUuid);

    txChar = service->createCharacteristic(
        ble::kTxCharacteristicUuid,
        BLECharacteristic::PROPERTY_NOTIFY | BLECharacteristic::PROPERTY_READ);
    txChar->addDescriptor(new BLE2902());

    BLECharacteristic* rxChar = service->createCharacteristic(
        ble::kRxCharacteristicUuid,
        BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
    rxChar->setCallbacks(new RxCallbacks());

    service->start();

    BLEAdvertising* advertising = BLEDevice::getAdvertising();
    advertising->addServiceUUID(ble::kServiceUuid);
    advertising->setScanResponse(true);
    advertising->setMinPreferred(0x06);
    BLEDevice::startAdvertising();
}

bool takePending(Frame& out) {
    return blePendingQueue != nullptr && xQueueReceive(blePendingQueue, &out, 0) == pdTRUE;
}

void notifyAck(const Frame& frame) {
    if (!clientConnected || txChar == nullptr) return;
    char msg[32];
    int len = std::snprintf(msg, sizeof(msg), "ACK:%u:%u",
                            static_cast<unsigned>(frame.node_id),
                            static_cast<unsigned>(frame.seq));
    if (len > 0) {
        txChar->setValue(reinterpret_cast<uint8_t*>(msg), static_cast<size_t>(len));
        txChar->notify();
    }
}

void notifyDownlink(const Frame& frame) {
    if (!clientConnected || txChar == nullptr) return;
    uint8_t buffer[kFrameSize];
    encode(frame, buffer);
    txChar->setValue(buffer, kFrameSize);
    txChar->notify();
}

}  // namespace ble_bridge
}  // namespace stg

#endif  // defined(ROLE_PORTABLE)
