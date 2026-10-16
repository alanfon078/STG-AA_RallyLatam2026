#include "portal.h"

#include <Arduino.h>
#include <DNSServer.h>
#include <ESPAsyncWebServer.h>
#include <LittleFS.h>
#include <WiFi.h>

#include "config.h"

namespace {

constexpr uint8_t kMaxClients = 8;
constexpr size_t kQueueDepth = 8;
constexpr const char* kCaptiveProbePaths[] = {
    "/generate_204", "/gen_204",          "/hotspot-detect.html", "/library/test/success.html",
    "/connecttest.txt", "/ncsi.txt",      "/fwlink",              "/redirect",
    "/canonical.html",  "/success.txt",
};

const IPAddress kApIp(192, 168, 4, 1);
const IPAddress kNetmask(255, 255, 255, 0);

DNSServer dnsServer;
AsyncWebServer server(80);
QueueHandle_t pendingQueue = nullptr;
uint16_t sequence = 0;

bool readDouble(AsyncWebServerRequest* request, const char* name, double& value) {
    if (!request->hasParam(name, true)) return false;
    String raw = request->getParam(name, true)->value();
    if (raw.length() == 0) return false;
    value = raw.toDouble();
    return true;
}

long readLong(AsyncWebServerRequest* request, const char* name, long fallback) {
    if (!request->hasParam(name, true)) return fallback;
    return request->getParam(name, true)->value().toInt();
}

void redirectToPortal(AsyncWebServerRequest* request) {
    request->redirect("http://192.168.4.1/");
}

void handleSos(AsyncWebServerRequest* request) {
    long kind = readLong(request, "kind", -1);
    if (kind < 0 || kind > stg::kMaxKind) {
        request->send(400, "application/json", "{\"ok\":false,\"error\":\"kind\"}");
        return;
    }

    double lat = NODE_LAT_E6 / 1e6;
    double lon = NODE_LON_E6 / 1e6;
    double reportedLat = 0;
    double reportedLon = 0;
    if (readDouble(request, "lat", reportedLat) && readDouble(request, "lon", reportedLon) &&
        reportedLat >= -90.0 && reportedLat <= 90.0 && reportedLon >= -180.0 &&
        reportedLon <= 180.0) {
        lat = reportedLat;
        lon = reportedLon;
    }

    long affected = constrain(readLong(request, "affected", 1), 0L, 999L);

    stg::Frame frame{};
    frame.version = stg::kVersion;
    frame.flags = 0;
    frame.kind = static_cast<uint8_t>(kind);
    frame.ttl = stg::kDefaultTtl;
    frame.node_id = NODE_ID;
    frame.seq = ++sequence;
    frame.node_time = millis() / 1000;
    frame.lat_e6 = lround(lat * 1e6);
    frame.lon_e6 = lround(lon * 1e6);
    frame.severity = 0;
    frame.affected = static_cast<uint16_t>(affected);

    if (xQueueSend(pendingQueue, &frame, 0) != pdTRUE) {
        request->send(503, "application/json", "{\"ok\":false,\"error\":\"busy\"}");
        return;
    }
    request->send(200, "application/json", "{\"ok\":true}");
}

}  // namespace

namespace stg {
namespace portal {

void begin() {
    pendingQueue = xQueueCreate(kQueueDepth, sizeof(Frame));
    LittleFS.begin(true);

    WiFi.mode(WIFI_AP);
    WiFi.softAPConfig(kApIp, kApIp, kNetmask);
    WiFi.softAP(kApSsid, nullptr, 1, 0, kMaxClients);
    dnsServer.start(53, "*", kApIp);

    for (const char* path : kCaptiveProbePaths) {
        server.on(path, HTTP_ANY, redirectToPortal);
    }
    server.on("/sos", HTTP_POST, handleSos);
    server.serveStatic("/", LittleFS, "/").setDefaultFile("index.html");
    server.onNotFound(redirectToPortal);
    server.begin();
}

void loop() {
    dnsServer.processNextRequest();
}

bool takePending(Frame& out) {
    return pendingQueue != nullptr && xQueueReceive(pendingQueue, &out, 0) == pdTRUE;
}

}  // namespace portal
}  // namespace stg
