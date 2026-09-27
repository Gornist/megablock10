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
 * Лист для проверки читаемости QR с панели без самой панели (docs/firmware-plan.md, Ф7): кадры ровно как на e-paper
 * (тот же рендер), напечатанные в физическом размере панели. Печатать из браузера в масштабе 100 % («по размеру страницы» —
 * выключить), линейка 50 мм на листе проверяет, что масштаб не съехал.
 *
 *   npm run display-print-sheet -- [--out data/display-print-sheet.html] [--pitch-mm 0.175] [--width 272 --height 792]
 *                                  [--ec M,L] [--db ./data/mb10-admin.sqlite [--containers id1,id2]] [--game-secret …]
 *
 * Без --db — типовые контейнеры на 1–4 слота (шард с текстом, демон на 4 кода), зашифрованные как в Мастерской.
 * M — уровень коррекции печати и дисплея; L — для сравнения (та же строка, модулей меньше; сейчас не используется).
 */
const { values } = parseArgs({
  options: {
    out: { type: "string", default: "./data/display-print-sheet.html" },
    "pitch-mm": { type: "string", default: "0.175" },
    width: { type: "string", default: "272" },
    height: { type: "string", default: "792" },
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
const wMm = (width * pitch).toFixed(2);
const hMm = (height * pitch).toFixed(2);

const pages = levels.map((ec) => {
  const cards = samples.map((s) => {
    try {
      const r = renderQrForDisplay(s.qr, width, height, undefined, ec);
      const moduleMm = (r.scale * pitch).toFixed(2);
      const warn = r.scale <= 1 ? " warn" : "";
      return `<figure>
  <img src="${bitmapToPngDataUrl(r)}" style="width:${wMm}mm;height:${hMm}mm" alt="">
  <figcaption class="${warn}"><b>${esc(s.title)}</b><br>QR v${r.qrVersion}, ${r.modules} мод.<br>${r.scale} px = ${moduleMm} мм на модуль<br>${s.qr.length} символов</figcaption>
</figure>`;
    } catch (err) {
      return `<figure><figcaption class="warn"><b>${esc(s.title)}</b><br>${esc((err as Error).message)}</figcaption></figure>`;
    }
  });
  return `<section>
  <h1>QR на панели ${width}×${height} — уровень коррекции ${ec}${ec === "M" ? " (как на печати и дисплее)" : " (эксперимент: та же строка)"}</h1>
  <p>Шаг пикселя ${pitch} мм — кадр ${wMm}×${hMm} мм, как на e-paper. Печатать в масштабе 100 %. Линейка должна быть ровно 50 мм:</p>
  <div class="ruler"></div>
  <div class="row">${cards.join("\n")}</div>
</section>`;
});

const rows = samples.flatMap((s) => levels.map((ec) => `<tr><td>${esc(s.title)}</td><td>${ec}</td><td></td><td></td><td></td><td></td></tr>`)).join("\n");

const html = `<!doctype html>
<html lang="ru"><head><meta charset="utf-8"><title>QR-дисплей: проверка читаемости</title>
<style>
  @page { size: A4; margin: 10mm; }
  body { font: 10pt/1.3 sans-serif; color: #000; background: #fff; margin: 0; }
  section { page-break-after: always; }
  h1 { font-size: 13pt; margin: 0 0 2mm; }
  p { margin: 0 0 2mm; }
  .ruler { width: 50mm; height: 3mm; border: 0.3mm solid #000; border-top: 0; margin-bottom: 4mm;
           background: repeating-linear-gradient(90deg, #000 0 0.3mm, transparent 0.3mm 10mm); }
  .row { display: flex; gap: 2mm; flex-wrap: wrap; }
  figure { margin: 0; }
  img { display: block; outline: 0.2mm dashed #999; image-rendering: pixelated; }
  figcaption { font-size: 8pt; margin-top: 1mm; max-width: ${wMm}mm; }
  figcaption.warn { color: #b00; }
  table { border-collapse: collapse; width: 100%; font-size: 9pt; }
  td, th { border: 0.2mm solid #000; padding: 1.5mm; text-align: left; }
  td:nth-child(n+3) { width: 22%; }
</style></head><body>
${pages.join("\n")}
<section>
  <h1>Результаты: телефоны игроков, приложение Мегаблока</h1>
  <p>Для каждого кадра: модель телефона, с какого расстояния читается, при каком свете (день / вечер / фонарик / подсветка), прочитал ли за 3 с.
  Пунктирная рамка — край панели; QR в середине, остальное — белое поле e-paper.</p>
  <table><tr><th>Контейнер</th><th>Коррекция</th><th>Телефон</th><th>Расстояние</th><th>Свет</th><th>Прочитал?</th></tr>
  ${rows}
  </table>
</section>
</body></html>
`;

mkdirSync(dirname(values.out!), { recursive: true });
writeFileSync(values.out!, html);
console.log(`${values.out}: ${samples.length} контейнеров × уровни ${levels.join(", ")}; печатать в масштабе 100 %`);
