import {
  BacklightLevel,
  crc32,
  encodeBacklightPayload,
  encodeFrame,
  encodeHello,
  encodeNackPayload,
  encodeSecondsPayload,
  Format,
  HEADER_SIZE,
  MAX_PAYLOAD,
  MsgType,
  NackCode,
  PROTOCOL_VERSION,
  type HelloStatus,
} from "./protocol.js";

/**
 * Общие тестовые векторы протокола дисплеев: сервер (protocol.ts) и прошивка (firmware/display, ядро на C++) проверяют себя по
 * одному файлу firmware/display/test/vectors/protocol-v1.json — так же, как lootCrypto на сервере и LootCrypto.kt на телефоне
 * закреплены общим тестовым hex. Файл пишет `npm run display-vectors`; серверный тест (displayVectors.test.ts) падает, если файл
 * разошёлся с тем, что даёт protocol.ts сейчас, — поменяли протокол, забыли векторы — красный тест.
 *
 * Всё детерминировано: фиксированные ключ, nonce и «кадр». Панель маленькая (20×10, строка 3 байта — ширина не кратна 8), чтобы
 * файл был читаемым; размер панели для протокола — просто числа.
 */

export const VECTORS_PATH_FROM_SERVER = "../../firmware/display/test/vectors/protocol-v1.json";

/** Что дисплей должен сделать с кадром (порядок проверок — docs/displays.md). */
export type Expect =
  | { action: "accept" }
  | { action: "nack"; code: keyof typeof NackCode }
  /** Граница кадра потеряна: NACK с кодом и закрыть соединение. */
  | { action: "close"; code: keyof typeof NackCode }
  /** Кадр ещё не дошёл целиком — ждать (или закрыть по таймауту payload). */
  | { action: "incomplete" };

export interface FrameVector {
  name: string;
  description: string;
  hex: string;
  expect: Expect;
}

export interface ReplyVector {
  name: string;
  /** Как дисплей собирает ответ: тип, seq, payload — байты должны совпасть. */
  type: keyof typeof MsgType;
  seq: number;
  payloadHex: string;
  hex: string;
}

export interface ProtocolVectors {
  comment: string;
  protocolVersion: number;
  headerSize: number;
  maxPayload: number;
  deviceId: string;
  keyHex: string;
  nonceHex: string;
  panel: { width: number; height: number; displayedVersion: number };
  crc32: { asciiInput: string; crc: number }[];
  hello: { statusJson: string; displayedVersion: number; hex: string };
  frames: FrameVector[];
  replies: ReplyVector[];
}

const hex = (b: Uint8Array) => Buffer.from(b).toString("hex");

export function buildProtocolVectors(): ProtocolVectors {
  const deviceId = "display-017";
  const key = Buffer.from(Array.from({ length: 32 }, (_, i) => i + 1));
  const nonce = Buffer.from(Array.from({ length: 16 }, (_, i) => 0xa0 + i));
  const otherNonce = Buffer.from(Array.from({ length: 16 }, (_, i) => 0x10 + i));
  const otherKey = Buffer.from(Array.from({ length: 32 }, (_, i) => 0xff - i));
  const panel = { width: 20, height: 10, displayedVersion: 141 };
  const stride = Math.ceil(panel.width / 8);
  const image = Buffer.from(Array.from({ length: stride * panel.height }, (_, i) => (i * 37 + 11) & 0xff));

  const imageFields = (seq: number, over: Partial<{ deviceId: string; width: number; payload: Buffer }> = {}) => ({
    type: MsgType.IMAGE,
    deviceId: over.deviceId ?? deviceId,
    seq,
    width: over.width ?? panel.width,
    height: panel.height,
    format: Format.BPP1,
    payload: over.payload ?? image,
  });
  const frame = (f: Parameters<typeof encodeFrame>[0], k = key, n = nonce) => encodeFrame(f, k, n);
  const command = (type: number, payload: Buffer) => frame({ type, deviceId, payload });

  const ok = frame(imageFields(142));
  const badMagic = Buffer.from(ok);
  badMagic[0] = 0x58;
  const badVersion = Buffer.from(ok);
  badVersion[5] = PROTOCOL_VERSION + 1;
  const oversize = Buffer.from(ok.subarray(0, HEADER_SIZE));
  oversize.writeUInt32BE(MAX_PAYLOAD + 1, 52);
  const badCrc = Buffer.from(ok);
  badCrc[HEADER_SIZE + 3] ^= 0x01;
  const tamperedSeq = Buffer.from(ok);
  tamperedSeq.writeUInt32BE(999, 40);

  const frames: FrameVector[] = [
    { name: "image_ok", description: "IMAGE версии 142 при показанной 141", hex: hex(ok), expect: { action: "accept" } },
    { name: "bad_magic", description: "первый байт MAGIC испорчен", hex: hex(badMagic), expect: { action: "close", code: "BAD_MAGIC" } },
    { name: "bad_version", description: "версия протокола 2", hex: hex(badVersion), expect: { action: "close", code: "BAD_VERSION" } },
    { name: "oversize_length", description: "только заголовок, длина payload больше допустимой", hex: hex(oversize), expect: { action: "close", code: "BAD_LENGTH" } },
    { name: "truncated", description: "заголовок и часть payload", hex: hex(ok.subarray(0, ok.length - 5)), expect: { action: "incomplete" } },
    { name: "header_only_partial", description: "меньше 92 байт заголовка", hex: hex(ok.subarray(0, 50)), expect: { action: "incomplete" } },
    { name: "bad_crc", description: "испорчен байт payload", hex: hex(badCrc), expect: { action: "nack", code: "BAD_CRC" } },
    { name: "wrong_key", description: "подписан чужим секретом", hex: hex(frame(imageFields(142), otherKey)), expect: { action: "nack", code: "AUTH_FAILED" } },
    { name: "other_nonce", description: "подписан nonce другого соединения", hex: hex(frame(imageFields(142), key, otherNonce)), expect: { action: "nack", code: "AUTH_FAILED" } },
    { name: "tampered_seq", description: "версия поднята после подписи", hex: hex(tamperedSeq), expect: { action: "nack", code: "AUTH_FAILED" } },
    { name: "wrong_device", description: "кадр для display-018", hex: hex(frame(imageFields(142, { deviceId: "display-018" }))), expect: { action: "nack", code: "WRONG_DEVICE" } },
    { name: "stale_equal", description: "версия равна показанной", hex: hex(frame(imageFields(141))), expect: { action: "nack", code: "STALE_VERSION" } },
    { name: "stale_older", description: "версия меньше показанной", hex: hex(frame(imageFields(100))), expect: { action: "nack", code: "STALE_VERSION" } },
    { name: "bad_width", description: "ширина кадра не та", hex: hex(frame(imageFields(142, { width: 24 }))), expect: { action: "nack", code: "BAD_FORMAT" } },
    { name: "bad_payload_size", description: "длина payload не stride×height", hex: hex(frame(imageFields(142, { payload: image.subarray(1) }))), expect: { action: "nack", code: "BAD_FORMAT" } },
    { name: "test_ok", description: "TEST на 30 с", hex: hex(command(MsgType.TEST, encodeSecondsPayload(30))), expect: { action: "accept" } },
    { name: "test_bad_length", description: "TEST без секунд", hex: hex(command(MsgType.TEST, Buffer.alloc(0))), expect: { action: "nack", code: "BAD_LENGTH" } },
    { name: "backlight_ok", description: "подсветка «средне» на 20 с", hex: hex(command(MsgType.BACKLIGHT, encodeBacklightPayload(BacklightLevel.MEDIUM, 20))), expect: { action: "accept" } },
    { name: "backlight_bad_level", description: "уровень 9", hex: hex(command(MsgType.BACKLIGHT, Buffer.from([9, 0, 20]))), expect: { action: "nack", code: "BAD_LENGTH" } },
    { name: "reboot_ok", description: "REBOOT", hex: hex(command(MsgType.REBOOT, Buffer.alloc(0))), expect: { action: "accept" } },
    { name: "unknown_type", description: "тип 0x7f", hex: hex(command(0x7f, Buffer.alloc(0))), expect: { action: "nack", code: "UNSUPPORTED_TYPE" } },
  ];

  const reply = (name: string, type: MsgType, seq: number, payload: Buffer = Buffer.alloc(0)): ReplyVector => ({
    name,
    type: MsgType[type] as keyof typeof MsgType,
    seq,
    payloadHex: hex(payload),
    hex: hex(encodeFrame({ type, deviceId, seq, width: panel.width, height: panel.height, format: Format.BPP1, payload }, key, nonce)),
  });

  const status: HelloStatus = { fw: "0.1.0", hw: "24:0a:c4:00:00:17", batteryMv: 3910, rssi: -61 };
  return {
    comment: "Сгенерировано admin-web/server: npm run display-vectors. Не править руками — см. src/displays/vectors.ts.",
    protocolVersion: PROTOCOL_VERSION,
    headerSize: HEADER_SIZE,
    maxPayload: MAX_PAYLOAD,
    deviceId,
    keyHex: hex(key),
    nonceHex: hex(nonce),
    panel,
    crc32: ["", "123456789", "MB10D"].map((s) => ({ asciiInput: s, crc: crc32(Buffer.from(s, "ascii")) })),
    hello: { statusJson: JSON.stringify(status), displayedVersion: panel.displayedVersion, hex: hex(encodeHello(deviceId, key, nonce, panel.displayedVersion, panel.width, panel.height, status)) },
    frames,
    replies: [
      reply("received", MsgType.RECEIVED, 142),
      reply("displayed", MsgType.DISPLAYED, 142),
      reply("nack_bad_crc", MsgType.NACK, 141, encodeNackPayload(NackCode.BAD_CRC)),
      reply("nack_stale_with_text", MsgType.NACK, 141, encodeNackPayload(NackCode.STALE_VERSION, "shows 141")),
      reply("ok", MsgType.OK, 141),
    ],
  };
}

export function protocolVectorsJson(): string {
  return `${JSON.stringify(buildProtocolVectors(), null, 2)}\n`;
}
