#!/bin/bash
# Собирает RNNoise и самопроверку обычным cc и запускает (хост, не Android): ослабление шума ≥ 10 дБ, тишина остаётся тишиной.
set -e
D=$(cd "$(dirname "$0")/.." && pwd)
OUT=${TMPDIR:-/tmp}/mb10-rnnoise-check
mkdir -p "$OUT"
cc -O2 -I"$D/rnnoise/include" -I"$D/rnnoise/src" -I"$D" \
  "$D"/rnnoise/src/{denoise,rnn,rnn_data,pitch,kiss_fft,celt_lpc}.c "$D/mb10_rnnoise.c" "$D/check/denoise_check.c" -lm -o "$OUT/denoise_check"
"$OUT/denoise_check"
