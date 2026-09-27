import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { decodeFrame, FrameReader, NackCode, ProtocolError, validateIncoming } from "./displays/protocol.js";
import { buildProtocolVectors, protocolVectorsJson, VECTORS_PATH_FROM_SERVER } from "./displays/vectors.js";

const vectorsPath = join(dirname(fileURLToPath(import.meta.url)), "..", VECTORS_PATH_FROM_SERVER);

test("общие векторы протокола в firmware/ совпадают с protocol.ts (иначе: npm run display-vectors)", () => {
  assert.equal(readFileSync(vectorsPath, "utf8"), protocolVectorsJson(), "векторы устарели — npm run display-vectors и закоммитить вместе с правкой протокола");
});

test("ожидания в векторах совпадают с эталонной проверкой сервера (validateIncoming)", () => {
  const v = buildProtocolVectors();
  const key = Buffer.from(v.keyHex, "hex");
  const nonce = Buffer.from(v.nonceHex, "hex");
  const panel = { deviceId: v.deviceId, ...v.panel };
  for (const f of v.frames) {
    const bytes = Buffer.from(f.hex, "hex");
    const reader = new FrameReader();
    reader.push(bytes);
    let actual: string;
    try {
      const frame = reader.next();
      if (!frame) actual = "incomplete";
      else {
        const code = validateIncoming(frame, key, nonce, panel);
        actual = code === null ? "accept" : `nack:${NackCode[code]}`;
      }
    } catch (err) {
      assert.ok(err instanceof ProtocolError, f.name);
      actual = `close:${NackCode[err.code]}`;
    }
    const expected = f.expect.action === "accept" || f.expect.action === "incomplete" ? f.expect.action : `${f.expect.action}:${f.expect.code}`;
    assert.equal(actual, expected, f.name);
  }
  for (const r of v.replies) assert.equal(decodeFrame(Buffer.from(r.hex, "hex")).header.seq, r.seq, r.name);
});
