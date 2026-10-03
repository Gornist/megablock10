import { spawnSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { existsSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { createServer, type AddressInfo, type Server, type Socket } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { parseArgs } from "node:util";
import { openDb } from "../db/index.js";
import { FirmwareHostProcess, freePort } from "../displays/firmwareHostProcess.js";
import { displayConfigFromEnv } from "../displays/config.js";
import { DisplayManager, type OpResult } from "../displays/manager.js";
import { MockDisplay } from "../displays/mockDisplay.js";

/**
 * Нагрузка на отправку в дисплеи без железа (docs/firmware-plan.md, Ф6): N дисплеев — прошивка для ПК (display_host, то же
 * ядро, что на плате) или mock, если бинарника нет, — и настоящий DisplayManager. Групповая отправка на 1/5/10/30 дисплеев:
 * время до DISPLAYED по каждому, число одновременных соединений против DISPLAY_MAX_CONCURRENT; затем «зависший» дисплей
 * (процесс остановлен SIGSTOP: TCP принимает ядро, HELLO нет) — остальные не должны его ждать.
 *
 *   npm run display-load -- [--bin ../../firmware/display/build/display_host] [--counts 1,5,10,30] [--delay 3000]
 *                           [--max-concurrent 20] [--no-hung] [--netem "delay 80ms 20ms loss 3%"] [--json out.json]
 *
 * Таймауты и повторы — из DISPLAY_* (как у сервера), их и подбирать. --netem вешает `tc qdisc … netem` на lo (нужны sudo и
 * модуль sch_netem; в CI есть) и снимает в конце. Код выхода 1 — нарушено ожидание (не все DISPLAYED, превышен лимит
 * соединений, зависший задержал остальных).
 */
const { values } = parseArgs({
  options: {
    bin: { type: "string", default: process.env.FIRMWARE_HOST_BIN },
    counts: { type: "string", default: "1,5,10,30" },
    delay: { type: "string", default: "3000" },
    "max-concurrent": { type: "string" },
    "no-hung": { type: "boolean", default: false },
    netem: { type: "string" },
    json: { type: "string" },
  },
});

const W = 792; // дисплеи висят горизонтально — как прошивка для ПК по умолчанию
const H = 272;
const counts = values.counts!.split(",").map((s) => Number(s.trim())).filter((n) => n > 0);
const delayMs = Number(values.delay);
const useHost = !!values.bin && existsSync(values.bin);
const envConfig = displayConfigFromEnv();
const maxConcurrent = values["max-concurrent"] ? Number(values["max-concurrent"]) : envConfig.maxConcurrent;
const out = mkdtempSync(join(tmpdir(), "mb10-load-"));
const problems: string[] = [];

interface Target {
  id: string;
  port: number;
  secret: string;
  stop(): Promise<void>;
}

async function startHost(id: string): Promise<Target & { proc: FirmwareHostProcess }> {
  const fw = new FirmwareHostProcess({ bin: values.bin!, id, secret: randomBytes(32).toString("hex"), port: await freePort(), out, args: ["--delay", String(delayMs)] });
  await fw.start();
  return { id, port: fw.port, secret: fw.secret, proc: fw, stop: () => fw.stop() };
}

async function startMock(id: string): Promise<Target> {
  const secret = randomBytes(32).toString("hex");
  const mock = new MockDisplay({ deviceId: id, key: Buffer.from(secret, "hex"), width: W, height: H, host: "127.0.0.1", port: 0, displayDelayMs: delayMs });
  const port = await mock.start();
  return { id, port, secret, stop: () => mock.stop() };
}

/** «Зависший» дисплей: соединение принимается, но в ответ — тишина (у прошивки — SIGSTOP процесса). */
async function startHung(id: string): Promise<Target> {
  if (useHost) {
    const t = await startHost(id);
    t.proc.proc.kill("SIGSTOP"); // stop() сам шлёт SIGCONT перед SIGKILL
    return t;
  }
  const sockets = new Set<Socket>();
  const server: Server = createServer((s) => sockets.add(s));
  await new Promise<void>((r) => server.listen(0, "127.0.0.1", () => r()));
  return {
    id,
    port: (server.address() as AddressInfo).port,
    secret: randomBytes(32).toString("hex"),
    stop: async () => {
      for (const s of sockets) s.destroy();
      await new Promise<void>((r) => server.close(() => r()));
    },
  };
}

function netem(args: string[]): void {
  const r = spawnSync("sudo", ["-n", "tc", "qdisc", ...args], { encoding: "utf8" });
  if (r.status !== 0) throw new Error(`tc qdisc ${args.join(" ")}: ${r.stderr || r.error}`);
}

/** Строка QR длиной как у контейнера на 2 слота (≈760 символов): рендер на сервере — часть нагрузки. */
function qrFor(i: number, round: number): string {
  return `MB10:LOAD:v1:${i}:${round}:${randomBytes(560).toString("base64url")}`;
}

const pct = (xs: number[], p: number) => xs[Math.min(xs.length - 1, Math.floor((xs.length - 1) * p))];

interface RoundResult {
  name: string;
  displays: number;
  ms: number[];
  wallMs: number;
  maxSockets: number;
  failed: string[];
  hungMs?: number;
  hungOutcome?: string;
}

async function main(): Promise<void> {
  const total = Math.max(...counts);
  const withHung = !values["no-hung"];
  if (values.netem) {
    netem(["add", "dev", "lo", "root", "netem", ...values.netem.split(/\s+/)]);
    console.log(`netem на lo: ${values.netem}`);
  }
  console.log(`${total} дисплеев: ${useHost ? `прошивка для ПК (${values.bin})` : "mock (display_host не найден — --bin или FIRMWARE_HOST_BIN)"}, обновление панели ${delayMs} мс`);
  const targets: Target[] = [];
  for (let i = 0; i < total; i++) targets.push(await (useHost ? startHost : startMock)(`load-${String(i + 1).padStart(2, "0")}`));
  const hung = withHung ? await startHung("load-hung") : null;

  const db = openDb(":memory:");
  const lines: string[] = [];
  const manager = new DisplayManager(db, { ...envConfig, maxConcurrent, probeIntervalMs: 0, log: (l) => lines.push(l) });
  for (const t of [...targets, ...(hung ? [hung] : [])]) {
    manager.repo.create(t.id, { name: t.id, ip: "127.0.0.1", port: t.port, width: W, height: H, enabled: true }, t.secret);
  }
  // Открытые менеджером TCP-соединения (включая ещё не подключившиеся) — множество внутри менеджера; снимаем максимум.
  const sockets = (manager as unknown as { sockets: Set<unknown> }).sockets;

  const results: RoundResult[] = [];
  let round = 0;
  const runRound = async (name: string, ids: Target[], hungTarget: Target | null): Promise<RoundResult> => {
    round++;
    let maxSockets = 0;
    const sampler = setInterval(() => (maxSockets = Math.max(maxSockets, sockets.size)), 2);
    const started = Date.now();
    const timed = (id: string, r: Promise<OpResult>) => r.then((res) => ({ id, res, ms: Date.now() - started }));
    const hungPromise = hungTarget ? timed(hungTarget.id, manager.pushImage(hungTarget.id, qrFor(0, round), "hung").result) : null;
    const done = await Promise.all(ids.map((t, i) => timed(t.id, manager.pushImage(t.id, qrFor(i, round), name).result)));
    const wallMs = Date.now() - started;
    const hungDone = hungPromise ? await hungPromise : null;
    clearInterval(sampler);
    const ms = done.map((d) => d.ms).sort((a, b) => a - b);
    const failed = done.filter((d) => d.res.outcome !== "DISPLAYED").map((d) => `${d.id}: ${d.res.outcome} ${d.res.error ?? ""}`);
    const r: RoundResult = { name, displays: ids.length, ms, wallMs, maxSockets, failed, hungMs: hungDone?.ms, hungOutcome: hungDone?.res.outcome };
    const waves = Math.ceil((ids.length + (hungTarget ? 1 : 0)) / maxConcurrent);
    console.log(
      `${name.padEnd(16)} ${String(ids.length).padStart(3)} шт: до DISPLAYED мин ${ms[0]} / медиана ${pct(ms, 0.5)} / p90 ${pct(ms, 0.9)} / макс ${ms[ms.length - 1]} мс;` +
        ` соединений одновременно ≤ ${maxSockets} (лимит ${maxConcurrent}, волн ≥ ${waves})` +
        (hungDone ? `; зависший: ${hungDone.res.outcome} через ${hungDone.ms} мс` : ""),
    );
    for (const f of failed) console.log(`  не показано: ${f}`);
    if (failed.length) problems.push(`${name}: не показано ${failed.length} из ${ids.length}`);
    if (maxSockets > maxConcurrent) problems.push(`${name}: одновременно ${maxSockets} соединений при лимите ${maxConcurrent}`);
    results.push(r);
    return r;
  };

  try {
    for (const c of counts) await runRound(`группа ${c}`, targets.slice(0, c), null);
    if (hung) {
      // Та же группа, что и без зависшего, — сравнить хвост. Зависший держит один слот лимита до таймаута HELLO.
      const c = Math.min(10, total);
      const base = results.find((r) => r.displays === c) ?? (await runRound(`группа ${c}`, targets.slice(0, c), null));
      const r = await runRound(`${c} + зависший`, targets.slice(0, c), hung);
      const allowed = Math.round(base.ms[base.ms.length - 1] * 1.5 + 1000);
      if (r.ms[r.ms.length - 1] > allowed) problems.push(`зависший задержал остальных: макс ${r.ms[r.ms.length - 1]} мс против ${base.ms[base.ms.length - 1]} мс без него (допуск ${allowed})`);
      if (r.hungOutcome !== "FAILED") problems.push(`зависший дисплей: ${r.hungOutcome}, ждали FAILED`);
    }
  } finally {
    manager.stop();
    for (const t of [...targets, ...(hung ? [hung] : [])]) await t.stop();
    if (values.netem) netem(["del", "dev", "lo", "root"]);
    rmSync(out, { recursive: true, force: true });
  }

  const cfg = { ...envConfig, maxConcurrent, displayDelayMs: delayMs, netem: values.netem ?? null, firmware: useHost };
  console.log(
    `таймауты: connect ${cfg.connectTimeoutMs}, hello ${cfg.helloTimeoutMs}, received ${cfg.receivedTimeoutMs}, displayed ${cfg.displayedTimeoutMs} мс; повторы через ${cfg.retryDelaysMs.join(", ")} мс`,
  );
  if (values.json) writeFileSync(values.json, JSON.stringify({ config: cfg, rounds: results, problems }, null, 2));
  const retries = lines.filter((l) => /attempt=\d+ retryable=true/.test(l)).length;
  if (retries) console.log(`повторных попыток за прогон: ${retries}`);
  if (problems.length) {
    console.log(`НАРУШЕНО:\n${problems.map((p) => `  ${p}`).join("\n")}`);
    process.exitCode = 1;
  } else {
    console.log("OK: все кадры показаны, лимит соединений соблюдён" + (withHung ? ", зависший дисплей остальных не задержал" : ""));
  }
}

await main();
