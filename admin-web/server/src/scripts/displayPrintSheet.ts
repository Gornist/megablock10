import { mkdirSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import { parseArgs } from "node:util";
import { openDb } from "../db/index.js";
import { bitmapToPngDataUrl, renderQrForDisplay } from "../displays/renderer.js";
import { containerQrFromDb, containerQrString } from "../lib/containerQr.js";
import type { ContainerSlot } from "../lib/containerSlots.js";
import { encodeDaemonLoot, encodeShardLoot } from "../lib/lootCodec.js";
import { deriveLootKey, encryptLoot } from "../lib/lootCrypto.js";
import type { QrErrorCorrection } from "../lib/qrImage.js";

/**
 * Лист для проверки читаемости QR с панели без самой панели (docs/firmware-plan.md, Ф7): середина кадра ровно как на e-paper
 * (тот же рендер), напечатанная в физическом размере панели. Полный кадр 47,6×138,6 мм — четыре в ширину A4 не влезали,
 * поэтому на листе квадрат из середины панели (QR с тихой зоной целиком): сетка «контейнер × уровень коррекции» на одной
 * странице, таблица результатов — на второй. Печатать из браузера в масштабе 100 % («по размеру страницы» —
 * выключить), линейка 50 мм на листе проверяет, что масштаб не съехал.
 *
 *   npm run display-print-sheet -- [--out data/display-print-sheet.html] [--pitch-mm 0.175] [--width 792 --height 272]
 *                                  [--ec M,L] [--db ./data/mb10-admin.sqlite [--containers id1,id2]] [--game-secret …]
 *
 * Без --db — типовые контейнеры на 1–4 слота (шард с текстом, демон на 4 кода), зашифрованные как в Мастерской.
 * M — уровень коррекции печати и дисплея; L — для сравнения (та же строка, модулей меньше; сейчас не используется).
 */
const { values } = parseArgs({
  options: {
    out: { type: "string", default: "./data/display-print-sheet.html" },
    "pitch-mm": { type: "string", default: "0.175" },
    width: { type: "string", default: "792" },
    height: { type: "string", default: "272" },
    ec: { type: "string", default: "M,L" },
    db: { type: "string" },
    containers: { type: "string" },
    "game-secret": { type: "string" },
  },
});

const pitch = Number(values["pitch-mm"]);
const width = Number(values.width);
const height = Number(values.height);
const levels = values.ec!.split(",").map((s) => s.trim().toUpperCase()) as QrErrorCorrection[];

interface Sample {
  title: string;
  qr: string;
}

function sampleContainers(): Sample[] {
  const key = deriveLootKey(values["game-secret"] ?? process.env.GAME_SECRET ?? "print-sheet-sample");
  const shard = () =>
    encryptLoot(
      encodeShardLoot({ title: "Логи СБ за ночь", meta: "сектор 4", body: "Смена охраны в 03:00, код двери 4471. Не забыть отключить камеру.", valueHint: "ценно", decryptAction: false, moneyAmount: 200 }),
      key,
    );
  const daemon = () => encryptLoot(encodeDaemonLoot({ name: "Backdoor.exe", sequence: ["1C", "55", "BD", "E9"], tierLevel: 2, effect: "EXTRACT_SHARD" }), key);
  return [1, 2, 3, 4].map((n) => {
    const slots: ContainerSlot[] = Array.from({ length: n }, (_, i) => ({ index: i, type: i % 2 ? "DAEMON" : "SHARD", tier: "HARD", copies: 1, title: "t", payload: i % 2 ? daemon() : shard() }));
    return {
      title: `${n} ${n === 1 ? "слот" : "слота"}`,
      qr: containerQrString({ id: "container-1a2b3c4d", name: "Панель вентиляции, техэтаж", tier: "HARD", ownerFaction: "Otryad_SB", slots }),
    };
  });
}

function dbContainers(path: string): Sample[] {
  const db = openDb(path);
  const ids = values.containers
    ? values.containers.split(",").map((s) => s.trim())
    : (db.prepare(`SELECT id FROM containers ORDER BY name`).all() as { id: string }[]).map((r) => r.id);
  return ids.flatMap((id) => {
    const found = containerQrFromDb(db, id);
    if (!found.ok) {
      console.warn(`${id}: ${found.error} — пропущен`);
      return [];
    }
    return [{ title: found.name, qr: found.qr }];
  });
}

const samples = values.db ? dbContainers(values.db) : sampleContainers();
const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;");
// Полный кадр 47,6×138,6 мм: четыре в ширину A4 не влезают. QR занимает только середину панели, поэтому печатаем квадрат
// side×side из центра: масштаб рендера — от меньшей стороны (renderer.ts), так что пиксели те же, что на панели.
const side = Math.min(width, height);
const sideMm = (side * pitch).toFixed(2);

function cell(s: Sample, ec: QrErrorCorrection): string {
  try {
    const r = renderQrForDisplay(s.qr, side, side, undefined, ec);
    const moduleMm = (r.scale * pitch).toFixed(2);
    const warn = r.scale <= 1 ? " warn" : "";
    return `<td><img src="${bitmapToPngDataUrl(r)}" style="width:${sideMm}mm;height:${sideMm}mm" alt="">
  <div class="cap${warn}">${ec}: QR v${r.qrVersion}, ${r.modules} мод., ${r.scale} px = ${moduleMm} мм</div></td>`;
  } catch (err) {
    return `<td><div class="cap warn">${ec}: ${esc((err as Error).message)}</div></td>`;
  }
}

const gridRows = samples
  .map((s, i) => `<tr><th>№${i + 1}<br>${esc(s.title)}<br><span class="small">${s.qr.length} символов</span></th>${levels.map((ec) => cell(s, ec)).join("")}</tr>`)
  .join("\n");

const rows = samples
  .flatMap((s, i) => levels.map((ec) => `<tr><td>№${i + 1} ${esc(s.title)}</td><td>${ec}</td><td></td><td></td><td></td><td></td></tr>`))
  .join("\n");

const html = `<!doctype html>
<html lang="ru"><head><meta charset="utf-8"><title>QR-дисплей: проверка читаемости</title>
<style>
  @page { size: A4; margin: 10mm; }
  body { font: 10pt/1.3 sans-serif; color: #000; background: #fff; margin: 0; }
  section { page-break-after: always; }
  section:last-child { page-break-after: auto; }
  h1 { font-size: 13pt; margin: 0 0 2mm; }
  p { margin: 0 0 2mm; }
  .ruler { width: 50mm; height: 3mm; border: 0.3mm solid #000; border-top: 0; margin-bottom: 3mm;
           background: repeating-linear-gradient(90deg, #000 0 0.3mm, transparent 0.3mm 10mm); }
  table.grid { border-collapse: separate; border-spacing: 3mm 1.5mm; margin-left: -3mm; }
  table.grid th { font-size: 9pt; font-weight: normal; text-align: left; vertical-align: middle; width: 30mm; }
  table.grid td { vertical-align: top; }
  img { display: block; outline: 0.2mm dashed #999; image-rendering: pixelated; }
  .cap { font-size: 7.5pt; margin-top: 0.8mm; }
  .warn { color: #b00; }
  .small { font-size: 8pt; color: #444; }
  table.res { border-collapse: collapse; width: 100%; font-size: 9pt; }
  table.res td, table.res th { border: 0.2mm solid #000; padding: 1.8mm; text-align: left; }
  table.res td:nth-child(n+3) { width: 20%; }
</style></head><body>
<section>
  <h1>QR на e-paper ${width}×${height}: середина панели ${side}×${side} px в натуральную величину</h1>
  <p>Шаг пикселя ${pitch} мм — квадрат ${sideMm}×${sideMm} мм, ровно как на панели (остальная панель — белое поле). Печатать в масштабе 100 %
  («по размеру страницы» выключить). Линейка должна быть ровно 50 мм:</p>
  <div class="ruler"></div>
  <table class="grid"><tr><th></th>${levels.map((ec) => `<th>Коррекция ${ec}${ec === "M" ? " — как сейчас на печати и дисплее" : " — эксперимент, та же строка"}</th>`).join("")}</tr>
  ${gridRows}
  </table>
  <p class="small">Красная подпись — 1 px на модуль (≈${pitch} мм): вероятно, телефон не прочтёт.</p>
</section>
<section>
  <h1>Результаты: телефоны игроков, приложение Мегаблока</h1>
  <p>Сканировать приложением игроков (не системной камерой). Для каждого квадрата: модель телефона, с какого расстояния читается,
  при каком свете (день / вечер / фонарик), прочитал ли за 3 с. Вернуть лист (или фото) мастеру — по нему решаем: ≤ 2 слотов на контейнер,
  панель крупнее или коррекция L для дисплея.</p>
  <table class="res"><tr><th>Кадр</th><th>Коррекция</th><th>Телефон</th><th>Расстояние</th><th>Свет</th><th>Прочитал?</th></tr>
  ${rows}
  </table>
</section>
</body></html>
`;

mkdirSync(dirname(values.out!), { recursive: true });
writeFileSync(values.out!, html);
console.log(`${values.out}: ${samples.length} контейнеров × уровни ${levels.join(", ")}; печатать в масштабе 100 %`);
