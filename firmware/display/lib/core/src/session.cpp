#include "session.h"

#include <cstdio>
#include <cstring>

#include "util.h"

namespace mb10d {

Session::Session(Device& device, Link& link)
    : device_(device), link_(link), receiver_(device.incomingBuffer(), Device::incomingBytes(device.config())) {
  device_.platform().random(nonce_, sizeof nonce_);
  if (Sound* snd = device_.sound()) snd->resetUpload();
  lastActivity_ = device_.platform().nowMs();
  // HELLO: nonce ‖ статус; подписан этим же nonce.
  uint8_t payload[kNonceSize + kReplyPayloadMax];
  std::memcpy(payload, nonce_, kNonceSize);
  size_t json = device_.statusJson(reinterpret_cast<char*>(payload + kNonceSize), kReplyPayloadMax);
  reply(MsgType::Hello, device_.displayedVersion(), payload, kNonceSize + json);
}

void Session::reply(MsgType type, uint32_t seq, const uint8_t* payload, size_t len) {
  if (closed_) return;
  const Config& c = device_.config();
  uint8_t out[kHeaderSize + kNonceSize + kReplyPayloadMax];
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
  PanelState panel{c.deviceId, c.width, c.height, device_.displayedVersion(), device_.sound() != nullptr};
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
      handleAudio();
      break;
  }
}

// Звуковые команды: ответ — с seq запроса (сервер сверяет версию AUDIO_STATE и id объявления).
void Session::handleAudio() {
  const Header& h = receiver_.header();
  const uint8_t* p = receiver_.payload();
  Sound* snd = device_.sound();
  if (!snd) return;
  uint8_t u32[4];
  auto answer = [&](Nack code, const uint8_t* payload, size_t len) {
    if (code != Nack::None) nack(code);
    else reply(MsgType::Ok, h.seq, payload, len);
  };
  switch (static_cast<MsgType>(h.type)) {
    case MsgType::AudioState:
      answer(snd->applyState(h.seq, p, h.payloadLength), nullptr, 0);
      break;
    case MsgType::ClipBegin: {
      uint32_t have = 0;
      Nack code = snd->clipBegin(p, have);
      putU32(u32, have);
      answer(code, u32, 4);
      break;
    }
    case MsgType::ClipChunk: {
      uint32_t have = 0;
      Nack code = snd->clipChunk(p, h.payloadLength, have);
      putU32(u32, have);
      answer(code, u32, 4);
      break;
    }
    case MsgType::ClipCommit:
      answer(snd->clipCommit(), nullptr, 0);
      break;
    case MsgType::Announce: {
      uint32_t duration = 0;
      Nack code = snd->announce(h.seq, p, h.payloadLength, duration);
      char json[40];
      int n = std::snprintf(json, sizeof json, "{\"durationMs\":%u}", unsigned(duration));
      answer(code, reinterpret_cast<const uint8_t*>(json), size_t(n));
      break;
    }
    case MsgType::AnnounceStop:
      snd->stopAnnounce();
      answer(Nack::None, nullptr, 0);
      break;
    case MsgType::List: {
      char json[kListReplyMax + 1];
      size_t n = snd->listJson(getU16(p), json, sizeof json);
      answer(Nack::None, reinterpret_cast<const uint8_t*>(json), n);
      break;
    }
    default:
      break;
  }
}

void Session::poll() {
  if (closed_) return;
  uint32_t now = device_.platform().nowMs();
  const Config& c = device_.config();
  if (receiver_.partial() || inFrame_) {
    if (elapsed(now, frameStarted_, c.payloadTimeoutMs)) close("payload timeout — closing");
  } else if (elapsed(now, lastActivity_, c.headerTimeoutMs)) {
    close("header timeout — closing");
  }
}

}  // namespace mb10d
