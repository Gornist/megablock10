import { parseArgs } from "node:util";
import { runConformance } from "../displays/conformance.js";
import { DEFAULT_DISPLAY_PORT } from "../displays/protocol.js";

/**
 * Набор проверок совместимости дисплея (docs/firmware-plan.md): mock, прошивка для ПК, Wokwi, настоящая плата — одна команда.
 *
 *   npm run display-conformance -- --host 10.10.0.217 --id display-017 --secret <64 hex> [--port 47200] [--width 272 --height 792]
 *                                  [--only C2,C7] [--header-timeout 2000 --payload-timeout 5000 --display-timeout 15000] [--images 20]
 *
 * Код выхода 1, если хоть одна проверка не прошла. Прогон оставляет на дисплее тестовый узор — потом отправьте QR заново.
 */
const { values } = parseArgs({
  options: {
    host: { type: "string", default: "127.0.0.1" },
    port: { type: "string", default: String(DEFAULT_DISPLAY_PORT) },
    id: { type: "string" },
    secret: { type: "string" },
    width: { type: "string", default: "272" },
    height: { type: "string", default: "792" },
    only: { type: "string" },
    "header-timeout": { type: "string", default: "2000" },
    "payload-timeout": { type: "string", default: "5000" },
    "display-timeout": { type: "string", default: "15000" },
    images: { type: "string", default: "20" },
  },
});

if (!values.id || !values.secret || !/^[0-9a-f]{64}$/i.test(values.secret)) {
  console.error("usage: npm run display-conformance -- --host <ip> --id <display id> --secret <64 hex> [--port 47200] [--only C1,C2]");
  process.exit(2);
}

const results = await runConformance(
  {
    host: values.host!,
    port: Number(values.port),
    deviceId: values.id,
    key: Buffer.from(values.secret, "hex"),
    width: Number(values.width),
    height: Number(values.height),
  },
  {
    headerTimeoutMs: Number(values["header-timeout"]),
    payloadTimeoutMs: Number(values["payload-timeout"]),
    displayTimeoutMs: Number(values["display-timeout"]),
    imagesInRow: Number(values.images),
    log: (line) => console.log(line),
  },
  values.only?.split(",").map((s) => s.trim().toUpperCase()),
);
const failed = results.filter((r) => !r.ok);
console.log(`\n${results.length - failed.length} из ${results.length} проверок прошли${failed.length ? `; не прошли: ${failed.map((r) => r.id).join(", ")}` : ""}`);
process.exit(failed.length ? 1 : 0);
