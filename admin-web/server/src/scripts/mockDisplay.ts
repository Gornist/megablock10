import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { parseArgs } from "node:util";
import { MockDisplay } from "../displays/mockDisplay.js";
import { DEFAULT_DISPLAY_PORT } from "../displays/protocol.js";
import { bitmapToPng } from "../displays/renderer.js";

/**
 * Дисплей без железа для прогона дашборда на ПК (docs/displays.md, «Без железа»):
 *
 *   npm run mock-display -- --id display-017 --secret <hex из дашборда> [--port 47200] [--width 272 --height 792] [--delay 3000]
 *
 * Каждый показанный кадр пишется в <out>/<id>.png (откройте и наведите телефон — это тот же кадр, что уйдёт на e-paper),
 * версия — в <out>/<id>.json: после перезапуска mock «восстанавливает» её, как прошивка из flash.
 */
const { values } = parseArgs({
  options: {
    id: { type: "string" },
    secret: { type: "string" },
    port: { type: "string", default: String(DEFAULT_DISPLAY_PORT) },
    host: { type: "string", default: "0.0.0.0" },
    width: { type: "string", default: "272" },
    height: { type: "string", default: "792" },
    delay: { type: "string", default: "3000" },
    out: { type: "string", default: "./data/mock-display" },
  },
});

if (!values.id || !values.secret || !/^[0-9a-f]{64}$/i.test(values.secret)) {
  console.error("usage: npm run mock-display -- --id <display id> --secret <64 hex> [--port 47200] [--width 272 --height 792] [--delay 3000] [--out dir]");
  process.exit(2);
}

const id = values.id;
const out = values.out!;
mkdirSync(out, { recursive: true });
const statePath = join(out, `${id}.json`);
let displayedVersion = 0;
try {
  displayedVersion = (JSON.parse(readFileSync(statePath, "utf8")) as { displayedVersion: number }).displayedVersion;
} catch {
  // первый запуск — экран пуст
}

const width = Number(values.width);
const height = Number(values.height);
const mock = new MockDisplay({
  deviceId: id,
  key: Buffer.from(values.secret, "hex"),
  width,
  height,
  host: values.host,
  port: Number(values.port),
  displayedVersion,
  displayDelayMs: Number(values.delay),
  status: { fw: "mock-cli", hw: "mock", batteryMv: 3950, rssi: -55 },
  log: (line) => console.log(line),
  onDisplayed: (version, framebuffer) => {
    writeFileSync(join(out, `${id}.png`), bitmapToPng({ width, height, format: "1bpp", data: framebuffer }));
    writeFileSync(statePath, JSON.stringify({ displayedVersion: version, at: new Date().toISOString() }));
  },
});

mock.start().then((port) => console.log(`[MOCK ${id}] listening on ${values.host}:${port}, shows version ${displayedVersion}, frames → ${join(out, `${id}.png`)}`));
