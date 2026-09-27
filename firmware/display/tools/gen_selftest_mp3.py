#!/usr/bin/env python3
"""MP3 для самопроверки звука в Wokwi (docs/sound-nodes.md, З5): 1,5 с тона 440 Гц, 44,1 кГц моно, 32 кбит/с (≈ 6 КБ).
Самопроверка пишет его на эмулированную microSD как трек канала и проверяет, что декодер MP3 на плате его играет.

    pip install lameenc && python3 tools/gen_selftest_mp3.py > src/esp32/selftest_mp3.h
"""
import math
import struct

import lameenc

RATE = 44100
samples = [int(12000 * math.sin(2 * math.pi * 440 * i / RATE)) for i in range(int(RATE * 1.5))]
enc = lameenc.Encoder()
enc.set_bit_rate(32)
enc.set_in_sample_rate(RATE)
enc.set_channels(1)
enc.set_quality(7)
mp3 = enc.encode(struct.pack(f"<{len(samples)}h", *samples)) + enc.flush()

print("// Сгенерировано tools/gen_selftest_mp3.py — не править руками. 1,5 с тона 440 Гц, 44,1 кГц моно, 32 кбит/с.")
print("#pragma once")
print("#include <cstddef>")
print("#include <cstdint>")
print(f"constexpr size_t kSelftestMp3Size = {len(mp3)};")
print("const uint8_t kSelftestMp3[kSelftestMp3Size] = {")
for i in range(0, len(mp3), 24):
    print("  " + ", ".join(f"0x{b:02x}" for b in mp3[i:i + 24]) + ",")
print("};")
