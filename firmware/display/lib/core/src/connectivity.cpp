#include "connectivity.h"

#include <cstddef>

#include "util.h"

namespace mb10d {

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
      } else if (elapsed(now, since_, connectTimeoutMs_)) {
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
