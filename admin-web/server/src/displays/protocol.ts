import { createHmac, timingSafeEqual } from "node:crypto";

/**
 * Протокол «мастерский сервер ↔ электронный QR-дисплей» (docs/displays.md — полное описание для прошивки ESP32).
 *
 * Дисплей — TCP-сервер (порт по умолчанию DEFAULT_DISPLAY_PORT), сервер подключается к нему сам (push, не опрос с дисплея).
 * На каждое соединение дисплей первым шлёт HELLO со случайным nonce; дальше каждый кадр в обе стороны подписан
 * HMAC-SHA256(секрет дисплея, nonce ‖ заголовок без поля HMAC ‖ payload). Nonce свой у каждого соединения — записанный
 * кадр из прошлого соединения не пройдёт проверку; старую картинку внутри нового соединения не даст показать IMAGE_VERSION.
 *
 * Кадр (все числа big-endian):
 *
 *   смещ. размер поле
 *   0     5      MAGIC "MB10D"
 *   5     1      версия протокола (PROTOCOL_VERSION)
 *   6     1      тип сообщения (MsgType)
 *   7     1      флаги (0, зарезервировано)
 *   8     32     id дисплея, ASCII, добивается нулями
 *   40    4      seq: у IMAGE — версия картинки; у ответов дисплея — версия, которую он показывает (или о которой ответ)
 *   44    2      ширина кадра, px
 *   46    2      высота кадра, px
 *   48    1      формат (Format)
 *   49    3      зарезервировано (0)
 *   52    4      длина payload, байт
 *   56    4      CRC32 (IEEE, как у zlib) от payload
 *   60    32     HMAC-SHA256
 *   92    …      payload
 *
 * Дисплей ничего не знает о формате MB10: для него IMAGE — просто 1-битный кадр (Format.BPP1).
 */

export const MAGIC = Buffer.from("MB10D", "ascii");
export const PROTOCOL_VERSION = 1;
export const HEADER_SIZE = 92;
export const DEVICE_ID_SIZE = 32;
export const NONCE_SIZE = 16;
export const HMAC_OFFSET = 60;
export const HMAC_SIZE = 32;
/** Кадр 792×272 — 26 928 байт; с запасом на панели крупнее, но не столько, чтобы битая длина заставила копить мегабайты. */
export const MAX_PAYLOAD = 256 * 1024;
export const DEFAULT_DISPLAY_PORT = 47200;

export enum MsgType {
  /** Дисплей → сервер, первым на каждое соединение. payload: nonce[16] ‖ JSON-статус (HelloStatus). seq — показанная версия. */
  HELLO = 0x01,
  /** Сервер → дисплей: показать кадр. seq — версия картинки, payload — кадр в формате format, width×height. */
  IMAGE = 0x10,
  /** Сервер → дисплей: диагностический экран (id, Wi-Fi, IP, RSSI, прошивка) на N секунд, затем снова последний кадр. payload: u16 секунд. */
  TEST = 0x11,
  /** Сервер → дисплей: подсветка. payload: u8 уровень (BacklightLevel) ‖ u16 секунд до выключения (0 — пока не скажут иначе). */
  BACKLIGHT = 0x12,
  /** Сервер → дисплей: перезагрузка (после ответа OK). payload пуст. */
  REBOOT = 0x13,
  /** Дисплей → сервер: кадр IMAGE принят и проверен (длина, CRC, HMAC, версия). seq — версия кадра. */
  RECEIVED = 0x20,
  /** Дисплей → сервер: кадр сохранён во flash и e-paper обновлён. seq — версия кадра. */
  DISPLAYED = 0x21,
  /** Дисплей → сервер: отказ. payload: u8 код (NackCode) ‖ необязательный текст UTF-8. seq — версия, показанная сейчас. */
  NACK = 0x22,
  /** Дисплей → сервер: команда (TEST/BACKLIGHT/REBOOT) принята. */
  OK = 0x23,
}

export enum Format {
  NONE = 0,
  /** 1 бит на пиксель, строки сверху вниз, в байте старший бит — левый пиксель, строка добивается до целого байта; 1 — чёрный. */
  BPP1 = 1,
}

export enum NackCode {
  BAD_MAGIC = 1,
  BAD_VERSION = 2,
  BAD_LENGTH = 3,
  BAD_CRC = 4,
  AUTH_FAILED = 5,
  /** seq ≤ показанной версии: старый или повторный кадр. */
  STALE_VERSION = 6,
  /** Формат/размер кадра не совпал с панелью. */
  BAD_FORMAT = 7,
  WRONG_DEVICE = 8,
  BUSY = 9,
  /** Кадр принят, но e-paper не обновился (или не записался во flash). */
  DISPLAY_FAILED = 10,
  UNSUPPORTED_TYPE = 11,
}

export enum BacklightLevel {
  OFF = 0,
  LOW = 1,
  MEDIUM = 2,
  HIGH = 3,
}

export interface FrameHeader {
  version: number;
  type: number;
  flags: number;
  deviceId: string;
  seq: number;
  width: number;
  height: number;
  format: number;
  payloadLength: number;
  crc32: number;
  hmac: Buffer;
}

export interface Frame {
  header: FrameHeader;
  /** Первые 60 байт заголовка как пришли — подпись считается по ним, а не по пересобранным полям. */
  signedHeader: Buffer;
  payload: Buffer;
}

/** Статус из HELLO — всё необязательное: старая/урезанная прошивка может прислать меньше полей. */
export interface HelloStatus {
  /** Версия прошивки. */
  fw?: string;
  /** Аппаратный id (MAC) — для сопоставления платы с записью дисплея. */
  hw?: string;
  batteryMv?: number;
  /** Топливомер MAX17048: заряд, % (0…100) и скорость, % в час (минус — разряд). Без топливомера — не шлются. */
  batteryPct?: number;
  batteryRate?: number;
  rssi?: number;
  ip?: string;
  /** Состояние подсветки (BacklightLevel). */
  backlight?: number;
}

// ── CRC32 (IEEE 802.3, полином 0xEDB88320) — та же таблица пишется в прошивке, поэтому своя, а не zlib.crc32. ──

const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();

export function crc32(data: Uint8Array): number {
  let c = 0xffffffff;
  for (let i = 0; i < data.length; i++) c = CRC_TABLE[(c ^ data[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

// ── Кодирование ──

export interface FrameFields {
  type: MsgType;
  deviceId: string;
  seq?: number;
  width?: number;
  height?: number;
  format?: Format;
  payload?: Buffer;
}

function encodeHeader(f: FrameFields, payload: Buffer): Buffer {
  const id = Buffer.from(f.deviceId, "ascii");
  if (id.length > DEVICE_ID_SIZE) throw new Error(`device id longer than ${DEVICE_ID_SIZE} bytes`);
  const h = Buffer.alloc(HEADER_SIZE);
  MAGIC.copy(h, 0);
  h.writeUInt8(PROTOCOL_VERSION, 5);
  h.writeUInt8(f.type, 6);
  h.writeUInt8(0, 7);
  id.copy(h, 8);
  h.writeUInt32BE((f.seq ?? 0) >>> 0, 40);
  h.writeUInt16BE(f.width ?? 0, 44);
  h.writeUInt16BE(f.height ?? 0, 46);
  h.writeUInt8(f.format ?? Format.NONE, 48);
  h.writeUInt32BE(payload.length, 52);
  h.writeUInt32BE(crc32(payload), 56);
  return h;
}

export function computeHmac(key: Buffer, nonce: Buffer, signedHeader: Buffer, payload: Buffer): Buffer {
  return createHmac("sha256", key).update(nonce).update(signedHeader).update(payload).digest();
}

/** Собрать и подписать кадр. nonce — из HELLO этого соединения. */
export function encodeFrame(f: FrameFields, key: Buffer, nonce: Buffer): Buffer {
  const payload = f.payload ?? Buffer.alloc(0);
  const header = encodeHeader(f, payload);
  computeHmac(key, nonce, header.subarray(0, HMAC_OFFSET), payload).copy(header, HMAC_OFFSET);
  return Buffer.concat([header, payload]);
}

/** HELLO: nonce входит в payload и им же подписан. */
export function encodeHello(deviceId: string, key: Buffer, nonce: Buffer, displayedVersion: number, width: number, height: number, status: HelloStatus): Buffer {
  const payload = Buffer.concat([nonce, Buffer.from(JSON.stringify(status), "utf8")]);
  return encodeFrame({ type: MsgType.HELLO, deviceId, seq: displayedVersion, width, height, format: Format.BPP1, payload }, key, nonce);
}

export function encodeNackPayload(code: NackCode, message = ""): Buffer {
  return Buffer.concat([Buffer.from([code]), Buffer.from(message, "utf8")]);
}

export function encodeBacklightPayload(level: BacklightLevel, seconds: number): Buffer {
  const b = Buffer.alloc(3);
  b.writeUInt8(level, 0);
  b.writeUInt16BE(Math.max(0, Math.min(0xffff, Math.round(seconds))), 1);
  return b;
}

export function encodeSecondsPayload(seconds: number): Buffer {
  const b = Buffer.alloc(2);
  b.writeUInt16BE(Math.max(0, Math.min(0xffff, Math.round(seconds))), 0);
  return b;
}

// ── Разбор потока ──

/** Поток больше не разобрать (сбилась граница кадра) — соединение закрывается. code — что ответить NACK-ом, если отвечать. */
export class ProtocolError extends Error {
  constructor(
    readonly code: NackCode,
    message: string,
  ) {
    super(message);
  }
}

function parseHeader(h: Buffer): FrameHeader {
  if (!h.subarray(0, MAGIC.length).equals(MAGIC)) throw new ProtocolError(NackCode.BAD_MAGIC, "bad magic");
  const version = h.readUInt8(5);
  if (version !== PROTOCOL_VERSION) throw new ProtocolError(NackCode.BAD_VERSION, `unsupported protocol version ${version}`);
  const payloadLength = h.readUInt32BE(52);
  if (payloadLength > MAX_PAYLOAD) throw new ProtocolError(NackCode.BAD_LENGTH, `payload length ${payloadLength} exceeds ${MAX_PAYLOAD}`);
  const idRaw = h.subarray(8, 8 + DEVICE_ID_SIZE);
  const zero = idRaw.indexOf(0);
  return {
    version,
    type: h.readUInt8(6),
    flags: h.readUInt8(7),
    deviceId: idRaw.subarray(0, zero === -1 ? DEVICE_ID_SIZE : zero).toString("ascii"),
    seq: h.readUInt32BE(40),
    width: h.readUInt16BE(44),
    height: h.readUInt16BE(46),
    format: h.readUInt8(48),
    payloadLength,
    crc32: h.readUInt32BE(56),
    hmac: Buffer.from(h.subarray(HMAC_OFFSET, HMAC_OFFSET + HMAC_SIZE)),
  };
}

/**
 * Накопитель байтов из сокета: push(chunk), потом next() — целый кадр или null, если ещё не дошёл. Заголовок проверяется сразу,
 * как только пришли его 92 байта (magic, версия, длина) — битую длину не ждём до таймаута. pendingBytes — сколько лежит
 * недоразобранным: «оборванный кадр» — это pendingBytes > 0 на закрытии соединения.
 */
export class FrameReader {
  private buf: Buffer = Buffer.alloc(0);
  private header: FrameHeader | null = null;

  push(chunk: Buffer): void {
    this.buf = this.buf.length === 0 ? chunk : Buffer.concat([this.buf, chunk]);
  }

  get pendingBytes(): number {
    return this.buf.length;
  }

  next(): Frame | null {
    if (this.buf.length < HEADER_SIZE) return null;
    if (!this.header) this.header = parseHeader(this.buf);
    const total = HEADER_SIZE + this.header.payloadLength;
    if (this.buf.length < total) return null;
    const frame: Frame = {
      header: this.header,
      signedHeader: Buffer.from(this.buf.subarray(0, HMAC_OFFSET)),
      payload: Buffer.from(this.buf.subarray(HEADER_SIZE, total)),
    };
    this.buf = this.buf.subarray(total);
    this.header = null;
    return frame;
  }
}

/** Разбор одного кадра целиком (тесты, отладка). Недостающие байты — ProtocolError BAD_LENGTH. */
export function decodeFrame(data: Buffer): Frame {
  const reader = new FrameReader();
  reader.push(data);
  const frame = reader.next();
  if (!frame) throw new ProtocolError(NackCode.BAD_LENGTH, "truncated frame");
  if (reader.pendingBytes > 0) throw new ProtocolError(NackCode.BAD_LENGTH, "trailing bytes after frame");
  return frame;
}

// ── Проверки ──

/** CRC, затем HMAC: CRC отличает порчу при передаче (стоит повторить) от чужого/неверного секрета (повторять бесполезно). */
export function checkIntegrity(frame: Frame, key: Buffer, nonce: Buffer): NackCode | null {
  if (crc32(frame.payload) !== frame.header.crc32) return NackCode.BAD_CRC;
  const expected = computeHmac(key, nonce, frame.signedHeader, frame.payload);
  if (!timingSafeEqual(expected, frame.header.hmac)) return NackCode.AUTH_FAILED;
  return null;
}

/** HELLO: nonce из payload, проверка подписи им же. null — кадр не HELLO или слишком короткий. */
export function parseHello(frame: Frame): { nonce: Buffer; status: HelloStatus } | null {
  if (frame.header.type !== MsgType.HELLO || frame.payload.length < NONCE_SIZE) return null;
  let status: HelloStatus = {};
  try {
    const parsed = JSON.parse(frame.payload.subarray(NONCE_SIZE).toString("utf8") || "{}") as unknown;
    if (parsed && typeof parsed === "object") status = parsed as HelloStatus;
  } catch {
    // Статус — справочный; непонятный JSON не делает дисплей нерабочим.
  }
  return { nonce: Buffer.from(frame.payload.subarray(0, NONCE_SIZE)), status };
}

export interface PanelState {
  deviceId: string;
  width: number;
  height: number;
  displayedVersion: number;
}

/**
 * Проверка входящего кадра на стороне дисплея — эталон для прошивки (порядок проверок тот же) и основа mock-дисплея.
 * null — кадр принят; иначе код для NACK.
 */
export function validateIncoming(frame: Frame, key: Buffer, nonce: Buffer, panel: PanelState): NackCode | null {
  const h = frame.header;
  if (h.deviceId !== panel.deviceId) return NackCode.WRONG_DEVICE;
  const integrity = checkIntegrity(frame, key, nonce);
  if (integrity !== null) return integrity;
  switch (h.type) {
    case MsgType.IMAGE: {
      const stride = Math.ceil(panel.width / 8);
      if (h.format !== Format.BPP1 || h.width !== panel.width || h.height !== panel.height || h.payloadLength !== stride * panel.height) {
        return NackCode.BAD_FORMAT;
      }
      if (h.seq <= panel.displayedVersion) return NackCode.STALE_VERSION;
      return null;
    }
    case MsgType.TEST:
      return h.payloadLength === 2 ? null : NackCode.BAD_LENGTH;
    case MsgType.BACKLIGHT:
      return h.payloadLength === 3 && frame.payload[0] <= BacklightLevel.HIGH ? null : NackCode.BAD_LENGTH;
    case MsgType.REBOOT:
      return null;
    default:
      return NackCode.UNSUPPORTED_TYPE;
  }
}

export function nackCodeName(code: number): string {
  return NackCode[code] ?? `NACK_${code}`;
}
