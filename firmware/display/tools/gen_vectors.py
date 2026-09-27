#!/usr/bin/env python3
"""Общие векторы протокола (test/vectors/protocol-v1.json, их пишет admin-web: npm run display-vectors) → C++-заголовок для
тестов ядра. Тесты читают тот же файл, что и серверный тест, — через этот перевод, чтобы не тащить JSON-парсер в C++."""
import json
import sys


def s(v):
    return json.dumps(v, ensure_ascii=True)


src, dst = sys.argv[1], sys.argv[2]
v = json.load(open(src, encoding="utf-8"))
out = ["// Сгенерировано tools/gen_vectors.py из test/vectors/protocol-v1.json — не править.", "#pragma once", "#include <cstdint>", ""]
out.append(f"static const char* const kVecDeviceId = {s(v['deviceId'])};")
out.append(f"static const char* const kVecKeyHex = {s(v['keyHex'])};")
out.append(f"static const char* const kVecNonceHex = {s(v['nonceHex'])};")
out.append(f"static const uint16_t kVecWidth = {v['panel']['width']};")
out.append(f"static const uint16_t kVecHeight = {v['panel']['height']};")
out.append(f"static const uint32_t kVecDisplayed = {v['panel']['displayedVersion']};")
out.append(f"static const uint32_t kVecHeaderSize = {v['headerSize']};")
out.append(f"static const char* const kVecHelloStatus = {s(v['hello']['statusJson'])};")
out.append(f"static const uint32_t kVecHelloDisplayed = {v['hello']['displayedVersion']};")
out.append(f"static const char* const kVecHelloHex = {s(v['hello']['hex'])};")
out.append("struct CrcVector { const char* input; uint32_t crc; };")
out.append("static const CrcVector kVecCrc[] = {" + ", ".join(f"{{{s(c['asciiInput'])}, {c['crc']}u}}" for c in v["crc32"]) + "};")
out.append("struct FrameVector { const char* name; const char* hex; const char* action; const char* code; };")
out.append("static const FrameVector kVecFrames[] = {")
for f in v["frames"]:
    out.append(f"  {{{s(f['name'])}, {s(f['hex'])}, {s(f['expect']['action'])}, {s(f['expect'].get('code', ''))}}},")
out.append("};")
out.append("struct ReplyVector { const char* name; const char* type; uint32_t seq; const char* payloadHex; const char* hex; };")
out.append("static const ReplyVector kVecReplies[] = {")
for r in v["replies"]:
    out.append(f"  {{{s(r['name'])}, {s(r['type'])}, {r['seq']}u, {s(r['payloadHex'])}, {s(r['hex'])}}},")
out.append("};")
open(dst, "w", encoding="utf-8").write("\n".join(out) + "\n")
