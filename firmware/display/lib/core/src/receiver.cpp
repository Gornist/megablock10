#include "receiver.h"

#include <cstring>

namespace mb10d {

Receiver::Event Receiver::feed(const uint8_t* data, size_t len, size_t& consumed) {
  consumed = 0;
  if (error_ != Nack::None) return Event::Error;
  if (ready_) return Event::Frame;
  if (have_ < kHeaderSize) {
    size_t n = kHeaderSize - have_ < len ? kHeaderSize - have_ : len;
    std::memcpy(hdr_ + have_, data, n);
    have_ += n;
    consumed += n;
    if (have_ < kHeaderSize) return Event::NeedMore;
    error_ = parseHeader(hdr_, uint32_t(cap_), h_);
    if (error_ != Nack::None) return Event::Error;
  }
  size_t got = have_ - kHeaderSize;
  size_t need = h_.payloadLength - got;
  size_t n = need < len - consumed ? need : len - consumed;
  std::memcpy(payload_ + got, data + consumed, n);
  have_ += n;
  consumed += n;
  if (have_ - kHeaderSize < h_.payloadLength) return Event::NeedMore;
  ready_ = true;
  return Event::Frame;
}

void Receiver::next() {
  have_ = 0;
  ready_ = false;
}

}  // namespace mb10d
