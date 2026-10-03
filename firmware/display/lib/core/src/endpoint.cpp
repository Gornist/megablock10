#include "endpoint.h"

namespace mb10d {

void Endpoint::drop() {
  if (!link_) return;
  session_.reset();
  transport_.release(link_, true);
  link_ = nullptr;
}

void Endpoint::step() {
  if (Link* incoming = transport_.accept()) {
    if (link_) {
      device_.platform().log("new connection replaces the previous one");
      session_.reset();
      transport_.release(link_, false);
    }
    link_ = incoming;
    session_.reset(new Session(device_, *link_));
  }
  if (!link_) return;
  // Готовность спрашивать у текущего соединения и после accept: прежний цикл ПК брал её у вытесненного сокета (один poll на
  // «старый закрыт» и «пришёл новый») и звал блокирующий recv на новом, молчащем — цикл вставал навсегда (сбой C18–C20).
  bool gone = false;
  uint8_t buf[1460];
  while (!session_->closed() && transport_.readable(*link_)) {
    size_t n = transport_.read(*link_, buf, sizeof buf);
    if (n == 0) {
      gone = true;
      break;
    }
    session_->onData(buf, n);
    device_.platform().feedWatchdog();
  }
  session_->poll();
  if (gone || session_->closed() || link_->broken()) drop();
}

}  // namespace mb10d
