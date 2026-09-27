import { test } from "node:test";
import assert from "node:assert/strict";
import { inflateSync } from "node:zlib";
import { bitmapSize, bitmapToPng, getPixel, renderQrForDisplay, DEFAULT_QUIET_MODULES, type RenderedQr } from "./displays/renderer.js";
import { qrMatrix } from "./lib/qrImage.js";
import { containerQrString } from "./lib/containerQr.js";

const SHORT = "MB10:RAM:v1:ram-1a2b3c4d:1";
/** Контейнер на несколько слотов с шифрованным лутом — длинная строка, QR высокой версии. */
const LONG = containerQrString({
  id: "container-nasos-4",
  name: "Насосная-4, техэтаж",
  tier: "HARD",
  ownerFaction: "Otryad_SB",
  slots: Array.from({ length: 5 }, (_, i) => ({ index: i, type: "SHARD" as const, tier: "HARD", copies: 1, title: `s${i}`, payload: "A".repeat(90) })),
});

function darkCount(r: RenderedQr, x0: number, y0: number, w: number, h: number): number {
  let n = 0;
  for (let y = y0; y < y0 + h; y++) for (let x = x0; x < x0 + w; x++) if (getPixel(r, x, y)) n++;
  return n;
}

for (const [name, text] of [
  ["короткий QR (RAM)", SHORT],
  ["длинный QR контейнера", LONG],
] as const) {
  test(`${name}: кадр 272×792 1 бит, QR квадратный, по центру, модули совпадают с матрицей печати`, () => {
    const r = renderQrForDisplay(text, 272, 792);
    const matrix = qrMatrix(text);
    assert.equal(r.format, "1bpp");
    assert.equal(r.data.length, 26928);
    assert.equal(r.data.length, bitmapSize(272, 792));
    assert.equal(r.modules, matrix.size);
    assert.ok(r.scale >= 1 && Number.isInteger(r.scale));
    // Квадрат: сторона QR одинакова по обеим осям и влезает в короткую сторону.
    assert.equal(r.qrSizePx, (r.modules + 2 * DEFAULT_QUIET_MODULES) * r.scale);
    assert.ok(r.qrSizePx <= 272);
    // По центру (с точностью до пикселя от целочисленного деления).
    const left = r.offsetX - DEFAULT_QUIET_MODULES * r.scale;
    const top = r.offsetY - DEFAULT_QUIET_MODULES * r.scale;
    assert.ok(Math.abs(left - (272 - r.qrSizePx - left)) <= 1);
    assert.ok(Math.abs(top - (792 - r.qrSizePx - top)) <= 1);
    // Каждый модуль — сплошной квадрат scale×scale одного цвета (без сглаживания), цвет — как в матрице печатного QR.
    for (let row = 0; row < r.modules; row++) {
      for (let col = 0; col < r.modules; col++) {
        const n = darkCount(r, r.offsetX + col * r.scale, r.offsetY + row * r.scale, r.scale, r.scale);
        assert.equal(n, matrix.dark(row, col) ? r.scale * r.scale : 0, `module ${row},${col}`);
      }
    }
    // Тихая зона и всё вне QR — белые: чёрных пикселей ровно столько, сколько тёмных модулей.
    let darkModules = 0;
    for (let row = 0; row < r.modules; row++) for (let col = 0; col < r.modules; col++) if (matrix.dark(row, col)) darkModules++;
    assert.equal(darkCount(r, 0, 0, 272, 792), darkModules * r.scale * r.scale);
    const quiet = DEFAULT_QUIET_MODULES * r.scale;
    assert.equal(darkCount(r, r.offsetX - quiet, r.offsetY - quiet, r.qrSizePx, quiet), 0, "тихая зона сверху");
    assert.equal(darkCount(r, r.offsetX - quiet, r.offsetY - quiet, quiet, r.qrSizePx), 0, "тихая зона слева");
  });
}

test("масштаб — наибольший целый, при котором QR с тихой зоной влезает в короткую сторону", () => {
  const short = renderQrForDisplay(SHORT, 272, 792);
  assert.equal(short.scale, Math.floor(272 / (short.modules + 8)));
  const long = renderQrForDisplay(LONG, 272, 792);
  assert.ok(long.modules > short.modules);
  assert.ok(long.scale < short.scale, "длинная строка — больше модулей, модуль мельче");
  // Ориентация не важна: у альбомной панели ограничивает высота.
  assert.equal(renderQrForDisplay(SHORT, 792, 272).scale, short.scale);
});

test("ширина не кратна 8 — строка кадра добивается до байта", () => {
  const r = renderQrForDisplay(SHORT, 250, 122);
  assert.equal(r.data.length, 32 * 122);
});

test("не влезает даже по пикселю на модуль — ошибка, а не обрезанный QR", () => {
  assert.throws(() => renderQrForDisplay(LONG, 40, 40), /does not fit/);
});

test("PNG предпросмотра: 1 бит оттенков серого, те же пиксели (1 — белый в PNG)", () => {
  const r = renderQrForDisplay(SHORT, 272, 792);
  const png = bitmapToPng(r);
  assert.deepEqual([...png.subarray(1, 4)], [0x50, 0x4e, 0x47]);
  assert.equal(png.readUInt32BE(16), 272);
  assert.equal(png.readUInt32BE(20), 792);
  assert.equal(png[24], 1);
  assert.equal(png[25], 0);
  const idatLen = png.readUInt32BE(33);
  const raw = inflateSync(png.subarray(41, 41 + idatLen));
  const stride = 34;
  for (let y = 0; y < 792; y += 37) {
    for (let x = 0; x < 272; x += 13) {
      const white = ((raw[y * (stride + 1) + 1 + (x >> 3)] >> (7 - (x & 7))) & 1) === 1;
      assert.equal(white, !getPixel(r, x, y));
    }
  }
});

test("горизонтальная панель 792×272 (так дисплеи и висят): тот же масштаб, что у портрета, QR по центру, остальное — белое", () => {
  const qr = "MB10:RAM:v1:ram-aaaa:1";
  const land = renderQrForDisplay(qr, 792, 272);
  const port = renderQrForDisplay(qr, 272, 792);
  assert.equal(land.scale, port.scale, "масштаб задаёт короткая сторона — 272 в обеих ориентациях");
  assert.equal(land.data.length, port.data.length, "26 928 байт в обеих ориентациях");
  const quiet = DEFAULT_QUIET_MODULES * land.scale;
  assert.equal(land.offsetX - quiet, Math.floor((792 - land.qrSizePx) / 2), "по центру по горизонтали");
  assert.equal(land.offsetY - quiet, Math.floor((272 - land.qrSizePx) / 2), "по центру по вертикали");
  let black = 0;
  for (let y = 0; y < 272; y++) for (let x = 0; x < 792; x++) if (getPixel(land, x, y)) black++;
  let blackInQr = 0;
  const x0 = land.offsetX - quiet;
  const y0 = land.offsetY - quiet;
  for (let y = y0; y < y0 + land.qrSizePx; y++) for (let x = x0; x < x0 + land.qrSizePx; x++) if (getPixel(land, x, y)) blackInQr++;
  assert.ok(black > 0);
  assert.equal(black, blackInQr, "вне квадрата QR — ни одного чёрного пикселя");
});
