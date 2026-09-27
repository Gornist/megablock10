import { deflateSync } from "node:zlib";
import { qrMatrix, type QrErrorCorrection } from "../lib/qrImage.js";
import { crc32 } from "./protocol.js";

/**
 * Строка QR → 1-битный кадр под конкретную панель. Сама строка приходит из того же места, что и для печати (lib/containerQr.ts,
 * lib/qrImage.ts) — здесь только растеризация: чёрные модули на белом, целый масштаб (модуль — квадрат из scale×scale пикселей,
 * без сглаживания и без растяжения), тихая зона не меньше quietModules модулей, QR по центру панели. У вытянутой панели
 * (CrowPanel 5.79: 792×272, висит горизонтально) размер QR ограничен короткой стороной, остаток — белый.
 */

export const DEFAULT_QUIET_MODULES = 4;

export interface DisplayBitmap {
  width: number;
  height: number;
  format: "1bpp";
  /** Строки сверху вниз, старший бит — левый пиксель, строка добита до байта; 1 — чёрный (protocol.ts, Format.BPP1). */
  data: Buffer;
}

export interface RenderedQr extends DisplayBitmap {
  /** Версия QR и модулей по стороне. */
  qrVersion: number;
  modules: number;
  /** Пикселей на модуль. */
  scale: number;
  /** Сторона QR вместе с тихой зоной, px. */
  qrSizePx: number;
  /** Левый верхний угол первого модуля (без тихой зоны). */
  offsetX: number;
  offsetY: number;
}

export function bitmapStride(width: number): number {
  return Math.ceil(width / 8);
}

export function bitmapSize(width: number, height: number): number {
  return bitmapStride(width) * height;
}

export function getPixel(b: DisplayBitmap, x: number, y: number): boolean {
  const byte = b.data[y * bitmapStride(b.width) + (x >> 3)];
  return ((byte >> (7 - (x & 7))) & 1) === 1;
}

function fillRect(data: Buffer, stride: number, x0: number, y0: number, w: number, h: number): void {
  for (let y = y0; y < y0 + h; y++) {
    const row = y * stride;
    for (let x = x0; x < x0 + w; x++) data[row + (x >> 3)] |= 0x80 >> (x & 7);
  }
}

export function renderQrForDisplay(
  qrText: string,
  width: number,
  height: number,
  quietModules = DEFAULT_QUIET_MODULES,
  errorCorrection?: QrErrorCorrection,
): RenderedQr {
  if (!Number.isInteger(width) || !Number.isInteger(height) || width <= 0 || height <= 0) throw new Error("display size must be positive integers");
  const matrix = qrMatrix(qrText, errorCorrection);
  const withQuiet = matrix.size + 2 * quietModules;
  const scale = Math.floor(Math.min(width, height) / withQuiet);
  if (scale < 1) {
    throw new Error(`QR (${matrix.size} modules + quiet zone) does not fit ${width}×${height} even at 1 px per module`);
  }
  const stride = bitmapStride(width);
  const data = Buffer.alloc(stride * height); // 0 — белый
  const qrSizePx = withQuiet * scale;
  const offsetX = Math.floor((width - qrSizePx) / 2) + quietModules * scale;
  const offsetY = Math.floor((height - qrSizePx) / 2) + quietModules * scale;
  for (let r = 0; r < matrix.size; r++) {
    for (let c = 0; c < matrix.size; c++) {
      if (matrix.dark(r, c)) fillRect(data, stride, offsetX + c * scale, offsetY + r * scale, scale, scale);
    }
  }
  return { width, height, format: "1bpp", data, qrVersion: matrix.version, modules: matrix.size, scale, qrSizePx, offsetX, offsetY };
}

// ── Предпросмотр: тот же кадр как PNG (1 бит, оттенки серого) — мастер видит ровно то, что уйдёт на панель. ──

function pngChunk(type: string, data: Buffer): Buffer {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length, 0);
  const body = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body), 0);
  return Buffer.concat([len, body, crc]);
}

export function bitmapToPng(b: DisplayBitmap): Buffer {
  const stride = bitmapStride(b.width);
  const raw = Buffer.alloc((stride + 1) * b.height);
  for (let y = 0; y < b.height; y++) {
    raw[y * (stride + 1)] = 0; // фильтр None
    for (let i = 0; i < stride; i++) raw[y * (stride + 1) + 1 + i] = ~b.data[y * stride + i] & 0xff; // в PNG 1 — белый
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(b.width, 0);
  ihdr.writeUInt32BE(b.height, 4);
  ihdr[8] = 1; // бит на пиксель
  ihdr[9] = 0; // оттенки серого
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    pngChunk("IHDR", ihdr),
    pngChunk("IDAT", deflateSync(raw)),
    pngChunk("IEND", Buffer.alloc(0)),
  ]);
}

export function bitmapToPngDataUrl(b: DisplayBitmap): string {
  return `data:image/png;base64,${bitmapToPng(b).toString("base64")}`;
}
