import { test } from "node:test";
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import {
  crc32,
  decodeFrame,
  encodeFrame,
  encodeHello,
  Format,
  FrameReader,
  HEADER_SIZE,
  MAX_PAYLOAD,
  MsgType,
  NackCode,
  parseHello,
  ProtocolError,
  validateIncoming,
  checkIntegrity,
} from "./displays/protocol.js";

const key = randomBytes(32);
const nonce = randomBytes(16);
const panel = { deviceId: "display-017", width: 272, height: 792, displayedVersion: 141 };
const frameBytes = (272 / 8) * 792;

function image(seq = 142, overrides: { key?: Buffer; nonce?: Buffer; deviceId?: string; width?: number; payload?: Buffer } = {}) {
  return encodeFrame(
    {
      type: MsgType.IMAGE,
      deviceId: overrides.deviceId ?? panel.deviceId,
      seq,
      width: overrides.width ?? 272,
      height: 792,
      format: Format.BPP1,
      payload: overrides.payload ?? randomBytes(frameBytes),
    },
    overrides.key ?? key,
    overrides.nonce ?? nonce,
  );
}

function expectProtocolError(fn: () => unknown, code: NackCode) {
  assert.throws(fn, (err: unknown) => err instanceof ProtocolError && err.code === code);
}

test("CRC32 совпадает с эталонным значением IEEE (как у zlib и в прошивке)", () => {
  assert.equal(crc32(Buffer.from("123456789", "ascii")), 0xcbf43926);
  assert.equal(crc32(Buffer.alloc(0)), 0);
});

test("корректный кадр: разбирается, поля на месте, дисплей принимает", () => {
  const bytes = image();
  assert.equal(bytes.length, HEADER_SIZE + 26928);
  const frame = decodeFrame(bytes);
  assert.equal(frame.header.type, MsgType.IMAGE);
  assert.equal(frame.header.deviceId, "display-017");
  assert.equal(frame.header.seq, 142);
  assert.equal(frame.header.width, 272);
  assert.equal(frame.header.height, 792);
  assert.equal(frame.header.payloadLength, 26928);
  assert.equal(validateIncoming(frame, key, nonce, panel), null);
});

test("неверный magic — отказ сразу по заголовку", () => {
  const bytes = image();
  bytes[0] = "X".charCodeAt(0);
  expectProtocolError(() => decodeFrame(bytes), NackCode.BAD_MAGIC);
});

test("неподдерживаемая версия протокола", () => {
  const bytes = image();
  bytes[5] = 2;
  expectProtocolError(() => decodeFrame(bytes), NackCode.BAD_VERSION);
});

test("длина payload больше допустимой — отказ по заголовку, не дожидаясь байтов", () => {
  const bytes = image();
  bytes.writeUInt32BE(MAX_PAYLOAD + 1, 52);
  const reader = new FrameReader();
  reader.push(bytes.subarray(0, HEADER_SIZE));
  expectProtocolError(() => reader.next(), NackCode.BAD_LENGTH);
});

test("длина кадра не совпадает с панелью — BAD_FORMAT, картинку не показывать", () => {
  const frame = decodeFrame(image(142, { payload: randomBytes(100) }));
  assert.equal(validateIncoming(frame, key, nonce, panel), NackCode.BAD_FORMAT);
  const wide = decodeFrame(image(142, { width: 800 }));
  assert.equal(validateIncoming(wide, key, nonce, panel), NackCode.BAD_FORMAT);
});

test("битый payload — BAD_CRC (CRC проверяется раньше подписи: порчу при передаче стоит повторить)", () => {
  const bytes = image();
  bytes[HEADER_SIZE + 10] ^= 0x01;
  assert.equal(validateIncoming(decodeFrame(bytes), key, nonce, panel), NackCode.BAD_CRC);
});

test("чужой секрет, чужой nonce (запись прошлого соединения) или подменённый заголовок — AUTH_FAILED", () => {
  assert.equal(validateIncoming(decodeFrame(image(142, { key: randomBytes(32) })), key, nonce, panel), NackCode.AUTH_FAILED);
  assert.equal(validateIncoming(decodeFrame(image(142, { nonce: randomBytes(16) })), key, nonce, panel), NackCode.AUTH_FAILED);
  const tampered = image(142);
  tampered.writeUInt32BE(999, 40); // версию подняли, подпись старая
  assert.equal(validateIncoming(decodeFrame(tampered), key, nonce, panel), NackCode.AUTH_FAILED);
});

test("кадр другому дисплею — WRONG_DEVICE", () => {
  assert.equal(validateIncoming(decodeFrame(image(142, { deviceId: "display-018" })), key, nonce, panel), NackCode.WRONG_DEVICE);
});

test("старая или та же версия картинки — STALE_VERSION", () => {
  assert.equal(validateIncoming(decodeFrame(image(141)), key, nonce, panel), NackCode.STALE_VERSION);
  assert.equal(validateIncoming(decodeFrame(image(100)), key, nonce, panel), NackCode.STALE_VERSION);
  assert.equal(validateIncoming(decodeFrame(image(142)), key, nonce, panel), null);
});

test("оборванный кадр: не выдаётся, пока не дошёл целиком; decodeFrame — ошибка", () => {
  const bytes = image();
  const reader = new FrameReader();
  reader.push(bytes.subarray(0, 50));
  assert.equal(reader.next(), null);
  reader.push(bytes.subarray(50, HEADER_SIZE + 1000));
  assert.equal(reader.next(), null);
  assert.equal(reader.pendingBytes, HEADER_SIZE + 1000);
  expectProtocolError(() => decodeFrame(bytes.subarray(0, bytes.length - 1)), NackCode.BAD_LENGTH);
  reader.push(bytes.subarray(HEADER_SIZE + 1000));
  assert.equal(reader.next()?.header.seq, 142);
  assert.equal(reader.pendingBytes, 0);
});

test("поток из нескольких кадров, порезанный как попало, разбирается по границам", () => {
  const stream = Buffer.concat([image(142), image(143), image(144)]);
  const reader = new FrameReader();
  const seqs: number[] = [];
  for (let i = 0; i < stream.length; i += 997) {
    reader.push(stream.subarray(i, i + 997));
    for (let f = reader.next(); f; f = reader.next()) seqs.push(f.header.seq);
  }
  assert.deepEqual(seqs, [142, 143, 144]);
});

test("HELLO: nonce и статус из payload, подпись проверяется этим же nonce", () => {
  const helloNonce = randomBytes(16);
  const frame = decodeFrame(encodeHello("display-017", key, helloNonce, 141, 272, 792, { fw: "0.1.0", batteryMv: 3900, rssi: -61 }));
  const hello = parseHello(frame)!;
  assert.deepEqual(hello.nonce, helloNonce);
  assert.deepEqual(hello.status, { fw: "0.1.0", batteryMv: 3900, rssi: -61 });
  assert.equal(frame.header.seq, 141);
  assert.equal(checkIntegrity(frame, key, hello.nonce), null);
  assert.equal(checkIntegrity(frame, randomBytes(32), hello.nonce), NackCode.AUTH_FAILED);
});

test("команды: неизвестный тип — UNSUPPORTED_TYPE, у подсветки проверяется длина и уровень", () => {
  const cmd = (type: number, payload: Buffer) => decodeFrame(encodeFrame({ type, deviceId: panel.deviceId, payload }, key, nonce));
  assert.equal(validateIncoming(cmd(0x7f, Buffer.alloc(0)), key, nonce, panel), NackCode.UNSUPPORTED_TYPE);
  assert.equal(validateIncoming(cmd(MsgType.BACKLIGHT, Buffer.from([2, 0, 10])), key, nonce, panel), null);
  assert.equal(validateIncoming(cmd(MsgType.BACKLIGHT, Buffer.from([9, 0, 10])), key, nonce, panel), NackCode.BAD_LENGTH);
  assert.equal(validateIncoming(cmd(MsgType.TEST, Buffer.from([0, 30])), key, nonce, panel), null);
  assert.equal(validateIncoming(cmd(MsgType.REBOOT, Buffer.alloc(0)), key, nonce, panel), null);
});
