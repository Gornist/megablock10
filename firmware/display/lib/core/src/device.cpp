#include "device.h"

#include <cstdarg>
#include <cstdio>
#include <cstring>

#include "crc32.h"

namespace mb10d {

const char* const kFrameFile = "frame.bin";

namespace {
const uint8_t kStoredMagic[4] = {'M', 'B', 'F', 'B'};
// «Прошло ли время t» с учётом переполнения millis() (≈49 суток).
inline bool reached(uint32_t now, uint32_t t) { return int32_t(now - t) >= 0; }
}  // namespace

Device::Device(const Config& cfg, Panel& panel, Storage& storage, Backlight& backlight, Platform& platform, uint8_t* frame, uint8_t* incoming)
    : cfg_(cfg), panel_(panel), storage_(storage), backlight_(backlight), platform_(platform), frame_(frame), incoming_(incoming) {}

void Device::logf(const char* fmt, ...) {
  char line[160];
  va_list ap;
  va_start(ap, fmt);
  std::vsnprintf(line, sizeof line, fmt, ap);
  va_end(ap);
  platform_.log(line);
}

void Device::boot() {
  backlight_.set(0);  // по умолчанию при загрузке подсветка выключена
  uint8_t head[kStoredHeaderSize];
  size_t size = frameSize();
  if (!storage_.read(kFrameFile, 0, head, sizeof head)) {
    logf("boot: no stored frame, screen stays as is");
    return;
  }
  uint32_t version = getU32(head + 4);
  if (std::memcmp(head, kStoredMagic, 4) != 0 || getU16(head + 8) != cfg_.width || getU16(head + 10) != cfg_.height || getU32(head + 12) != size) {
    logf("boot: stored frame is for another panel or corrupt — ignored");
    return;
  }
  if (!storage_.read(kFrameFile, kStoredHeaderSize, frame_, size) || crc32(frame_, size) != getU32(head + 16)) {
    logf("boot: stored frame %u failed CRC — ignored", unsigned(version));
    return;
  }
  displayed_ = version;
  hasFrame_ = true;
  logf("boot: restoring frame %u", unsigned(version));
  platform_.feedWatchdog();
  // e-paper обычно и так держит этот кадр; перерисовка — на случай, если панель сбросилась без питания.
  if (!panel_.show(frame_, cfg_.width, cfg_.height)) logf("boot: panel update failed");
  platform_.feedWatchdog();
}

bool Device::showImage(uint32_t version, const uint8_t* data) {
  size_t size = frameSize();
  uint8_t head[kStoredHeaderSize];
  std::memcpy(head, kStoredMagic, 4);
  putU32(head + 4, version);
  putU16(head + 8, cfg_.width);
  putU16(head + 10, cfg_.height);
  putU32(head + 12, uint32_t(size));
  putU32(head + 16, crc32(data, size));
  platform_.feedWatchdog();
  // Сначала flash, потом панель: перезагрузка посреди обновления восстановит уже новый кадр, а не старый.
  if (!storage_.writeAtomic(kFrameFile, head, sizeof head, data, size)) {
    logf("image %u: storage write failed", unsigned(version));
    return false;
  }
  platform_.feedWatchdog();
  bool ok = panel_.show(data, cfg_.width, cfg_.height);
  platform_.feedWatchdog();
  if (!ok) {
    logf("image %u: panel update failed", unsigned(version));
    return false;
  }
  if (data != frame_) std::memcpy(frame_, data, size);
  displayed_ = version;
  hasFrame_ = true;
  testShown_ = false;
  logf("image %u displayed", unsigned(version));
  return true;
}

void Device::showTest(uint16_t seconds) {
  char l1[48], l2[48], l3[48], l4[48], l5[48], l6[48];
  std::snprintf(l1, sizeof l1, "DISPLAY TEST");
  std::snprintf(l2, sizeof l2, "ID: %s", cfg_.deviceId);
  std::snprintf(l3, sizeof l3, "WiFi: %s", platform_.ipAddress()[0] ? "OK" : "--");
  std::snprintf(l4, sizeof l4, "IP: %s", platform_.ipAddress()[0] ? platform_.ipAddress() : "--");
  std::snprintf(l5, sizeof l5, "RSSI: %d dBm", platform_.rssi());
  std::snprintf(l6, sizeof l6, "FW: %s  QR v%u", platform_.firmwareVersion(), unsigned(displayed_));
  const char* lines[] = {l1, l2, l3, l4, l5, l6};
  logf("test screen for %u s", unsigned(seconds));
  platform_.feedWatchdog();
  panel_.showText(lines, 6);
  platform_.feedWatchdog();
  testShown_ = true;
  testUntil_ = platform_.nowMs() + uint32_t(seconds) * 1000;
}

void Device::setBacklight(uint8_t level, uint16_t seconds) {
  backlight_level_ = level;
  backlight_.set(level);
  backlightTimer_ = level > 0 && seconds > 0;
  if (backlightTimer_) backlightOffAt_ = platform_.nowMs() + uint32_t(seconds) * 1000;
  logf("backlight %u for %u s", unsigned(level), unsigned(seconds));
}

void Device::tick() {
  uint32_t now = platform_.nowMs();
  if (backlightTimer_ && reached(now, backlightOffAt_)) {
    backlightTimer_ = false;
    backlight_level_ = 0;
    backlight_.set(0);
    logf("backlight off by timer");
  }
  if (testShown_ && reached(now, testUntil_)) {
    testShown_ = false;
    if (hasFrame_) {
      logf("test screen over — back to frame %u", unsigned(displayed_));
      platform_.feedWatchdog();
      panel_.show(frame_, cfg_.width, cfg_.height);
      platform_.feedWatchdog();
    }
  }
}

size_t Device::statusJson(char* out, size_t cap) {
  int n = std::snprintf(out, cap, "{\"fw\":\"%s\",\"hw\":\"%s\"", platform_.firmwareVersion(), platform_.hardwareId());
  auto append = [&](const char* fmt, auto value) {
    if (n >= 0 && size_t(n) < cap) n += std::snprintf(out + n, cap - size_t(n), fmt, value);
  };
  if (platform_.ipAddress()[0]) append(",\"ip\":\"%s\"", platform_.ipAddress());
  if (platform_.rssi() != 0) append(",\"rssi\":%d", platform_.rssi());
  if (platform_.batteryMillivolts() >= 0) append(",\"batteryMv\":%d", platform_.batteryMillivolts());
  append(",\"backlight\":%u", unsigned(backlight_level_));
  append("%s", "}");
  return n < 0 || size_t(n) >= cap ? 0 : size_t(n);
}

// ── Сессия ──

Session::Session(Device& device, Link& link)
    : device_(device), link_(link), receiver_(device.incomingBuffer(), device.frameSize() < 64 ? 64 : device.frameSize()) {
  device_.platform().random(nonce_, sizeof nonce_);
  lastActivity_ = device_.platform().nowMs();
  // HELLO: nonce ‖ статус; подписан этим же nonce.
  uint8_t payload[kNonceSize + 256];
  std::memcpy(payload, nonce_, kNonceSize);
  size_t json = device_.statusJson(reinterpret_cast<char*>(payload + kNonceSize), 256);
  reply(MsgType::Hello, device_.displayedVersion(), payload, kNonceSize + json);
}

void Session::reply(MsgType type, uint32_t seq, const uint8_t* payload, size_t len) {
  if (closed_) return;
  const Config& c = device_.config();
  uint8_t out[kHeaderSize + kNonceSize + 256 + 64];
  FrameOut f{type, c.deviceId, seq, c.width, c.height, Format::Bpp1, payload, len};
  size_t n = encodeFrame(f, c.key, nonce_, out, sizeof out);
  if (n > 0) link_.send(out, n);
}

void Session::nack(Nack code) {
  char line[64];
  std::snprintf(line, sizeof line, "NACK %s", nackName(code));
  device_.platform().log(line);
  uint8_t payload[1] = {uint8_t(code)};
  reply(MsgType::Nack, device_.displayedVersion(), payload, 1);
}

void Session::close(const char* why) {
  if (closed_) return;
  device_.platform().log(why);
  closed_ = true;
  link_.close();
}

void Session::onData(const uint8_t* data, size_t len) {
  if (closed_) return;
  uint32_t now = device_.platform().nowMs();
  lastActivity_ = now;
  while (len > 0 && !closed_) {
    if (!inFrame_) {
      inFrame_ = true;
      frameStarted_ = now;
    }
    size_t used = 0;
    Receiver::Event ev = receiver_.feed(data, len, used);
    data += used;
    len -= used;
    if (ev == Receiver::Event::Error) {
      // Граница кадра потеряна — дальше поток не разобрать.
      nack(receiver_.error());
      close("stream broken — closing");
      return;
    }
    if (ev == Receiver::Event::NeedMore) return;
    inFrame_ = false;
    handle();
    receiver_.next();
    // Обновление панели шло секунды — таймауты отсчитываются заново.
    lastActivity_ = now = device_.platform().nowMs();
  }
}

void Session::handle() {
  const Header& h = receiver_.header();
  const Config& c = device_.config();
  PanelState panel{c.deviceId, c.width, c.height, device_.displayedVersion()};
  Nack code = validateIncoming(h, receiver_.signedHeader(), receiver_.payload(), c.key, nonce_, panel);
  if (code != Nack::None) {
    nack(code);
    return;
  }
  const uint8_t* p = receiver_.payload();
  switch (static_cast<MsgType>(h.type)) {
    case MsgType::Image:
      reply(MsgType::Received, h.seq);
      if (device_.showImage(h.seq, p)) reply(MsgType::Displayed, h.seq);
      else nack(Nack::DisplayFailed);
      break;
    case MsgType::Test:
      // OK — сразу: сервер ждёт ответа секунды, а экран рисуется дольше.
      reply(MsgType::Ok, device_.displayedVersion());
      device_.showTest(getU16(p));
      break;
    case MsgType::Backlight:
      device_.setBacklight(p[0], getU16(p + 1));
      reply(MsgType::Ok, device_.displayedVersion());
      break;
    case MsgType::Reboot:
      reply(MsgType::Ok, device_.displayedVersion());
      close("reboot requested");
      device_.requestReboot();
      break;
    default:
      break;
  }
}

void Session::poll() {
  if (closed_) return;
  uint32_t now = device_.platform().nowMs();
  const Config& c = device_.config();
  if (receiver_.partial() || inFrame_) {
    if (int32_t(now - frameStarted_) >= int32_t(c.payloadTimeoutMs)) close("payload timeout — closing");
  } else if (int32_t(now - lastActivity_) >= int32_t(c.headerTimeoutMs)) {
    close("header timeout — closing");
  }
}

// ── Wi-Fi ──

uint32_t Backoff::next() {
  static const uint32_t steps[] = {1000, 2000, 4000, 8000, 16000, 30000};
  uint32_t d = steps[step_];
  if (size_t(step_) + 1 < sizeof steps / sizeof steps[0]) step_++;
  return d;
}

Connectivity::Action Connectivity::update(bool linkUp, uint32_t now) {
  if (!started_) {
    started_ = true;
    state_ = State::Connecting;
    since_ = now;
    return Action::StartConnect;
  }
  switch (state_) {
    case State::Connecting:
      if (linkUp) {
        state_ = State::Online;
        backoff_.reset();
      } else if (int32_t(now - since_) >= int32_t(connectTimeoutMs_)) {
        state_ = State::Backoff;
        retryAt_ = now + backoff_.next();
        return Action::Disconnected;
      }
      return Action::None;
    case State::Online:
      if (!linkUp) {
        state_ = State::Backoff;
        retryAt_ = now + backoff_.next();
        return Action::Disconnected;
      }
      return Action::None;
    case State::Backoff:
      if (linkUp) {
        state_ = State::Online;
        backoff_.reset();
        return Action::None;
      }
      if (reached(now, retryAt_)) {
        state_ = State::Connecting;
        since_ = now;
        return Action::StartConnect;
      }
      return Action::None;
  }
  return Action::None;
}

}  // namespace mb10d
