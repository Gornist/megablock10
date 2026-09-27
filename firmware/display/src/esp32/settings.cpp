// Настройки дисплея в NVS: id, секрет, размер панели, порт, Wi-Fi, необязательный статический адрес. Пишутся одной строкой
// JSON из дашборда в USB-консоли (`config {…}`, main.cpp), читаются при загрузке.
#include <ArduinoJson.h>
#include <Preferences.h>

#include "board.h"
#include "protocol.h"

using namespace mb10d;
using mb10esp::kDefaultPort;
using mb10esp::Settings;

Settings mb10esp::loadSettings() {
  Settings s;
  Preferences p;
  if (!p.begin("mb10d", true)) return s;
  String id = p.getString("id", "");
  size_t keyLen = p.getBytes("key", s.cfg.key, sizeof s.cfg.key);
  s.cfg.width = p.getUShort("w", 792);
  s.cfg.height = p.getUShort("h", 272);
  s.port = p.getUShort("port", kDefaultPort);
  s.ssid = p.getString("ssid", "");
  s.pass = p.getString("pass", "");
  s.ip = p.getString("ip", "");
  s.gateway = p.getString("gw", "");
  s.subnet = p.getString("mask", "");
  s.dns = p.getString("dns", "");
  s.cfg.audio = p.getBool("audio", false);
  p.end();
  if (id.isEmpty() || id.length() > kDeviceIdSize || keyLen != kKeySize || s.ssid.isEmpty()) return s;
  snprintf(s.cfg.deviceId, sizeof s.cfg.deviceId, "%s", id.c_str());
  s.configured = true;
  return s;
}

// Строка из дашборда (DisplaySecretResponse.provisioning + Wi-Fi): config {"id":…,"secret":…,"port":…,"width":…,"height":…,
// "wifiSsid":…,"wifiPassword":…[, "ip":…,"gateway":…,"subnet":…,"dns":…][, "roles":["display","audio"]]}
// roles с "audio" (или "audio":true) — точка со звуковой платой (docs/sound-nodes.md).
bool mb10esp::saveSettingsJson(const char* json, String& error) {
  JsonDocument doc;
  if (deserializeJson(doc, json)) {
    error = "not JSON";
    return false;
  }
  const char* id = doc["id"] | "";
  const char* secret = doc["secret"] | "";
  const char* ssid = doc["wifiSsid"] | "";
  uint8_t key[kKeySize];
  if (!*id || strlen(id) > kDeviceIdSize) error = "id: 1..32 chars";
  else if (!parseHex(secret, key, sizeof key)) error = "secret: 64 hex chars";
  else if (!*ssid) error = "wifiSsid is required";
  if (error.length()) return false;
  Preferences p;
  p.begin("mb10d", false);
  p.putString("id", id);
  p.putBytes("key", key, sizeof key);
  p.putUShort("w", doc["width"] | 792);
  p.putUShort("h", doc["height"] | 272);
  p.putUShort("port", doc["port"] | kDefaultPort);
  p.putString("ssid", ssid);
  p.putString("pass", doc["wifiPassword"] | "");
  p.putString("ip", doc["ip"] | "");
  p.putString("gw", doc["gateway"] | "");
  p.putString("mask", doc["subnet"] | "");
  p.putString("dns", doc["dns"] | "");
  bool audio = doc["audio"] | false;
  for (JsonVariant r : doc["roles"].as<JsonArray>()) audio = audio || r == "audio";
  p.putBool("audio", audio);
  p.end();
  return true;
}
