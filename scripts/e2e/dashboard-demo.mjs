#!/usr/bin/env node
// Видео веб-интерфейса мастера: обход дашборда по событиям, которые показаны в демо-ролике приложения (см. demo.sh).
// Запускать ПОСЛЕ demo.sh на том же стенде (данные — в БД сервера). Без зависимостей: Node ≥ 22 (встроенный WebSocket/fetch),
// Google Chrome (headless, управление по протоколу DevTools), ffmpeg. Chrome отдаёт кадры screencast только при изменении страницы —
// как screenrecord на телефоне, поэтому длительности кадров берутся из меток времени и склеиваются ffmpeg concat.
//   node scripts/e2e/dashboard-demo.mjs            → $E2E_DIR/dash/dashboard.mp4
import { spawn, execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const E2E_DIR = process.env.E2E_DIR ?? "/tmp/mb10-e2e";
const API = process.env.API ?? "http://localhost:8080";
const OUT = path.join(E2E_DIR, "dash");
const FRAMES = path.join(OUT, "frames");
const CHROME = process.env.CHROME ?? "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const W = 1280, H = 800;
const sleep = (s) => new Promise((r) => setTimeout(r, s * 1000));

fs.rmSync(OUT, { recursive: true, force: true });
fs.mkdirSync(FRAMES, { recursive: true });

// ── данные для подписей: берём из API, чтобы цифры в подписях были настоящими ──
const masterToken = fs.readFileSync(path.join(E2E_DIR, "master.txt"), "utf8").trim().split("\n").pop();
const login = await (await fetch(`${API}/api/auth/login`, {
  method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ name: "E2E", token: masterToken }),
})).json();
const get = async (p) => (await fetch(`${API}${p}`, { headers: { authorization: `Bearer ${login.sessionToken}` } })).json();
const players = await get("/api/players");
const byName = (n) => players.find((p) => p.callsign === n);
const alice = byName("Alice"), bob = byName("Bob");
if (!alice || !bob) throw new Error("на дашборде нет Alice и Bob — сначала demo.sh на свежем стенде");
const snap = (p) => get(`/api/players/${encodeURIComponent(p.publicKeyB64)}`);
const aliceSnap = await snap(alice), bobSnap = await snap(bob);
const names = (list, key) => list.map((x) => x[key]).join(", ") || "нет";
const overview = await get("/api/overview");
const nodes = await get("/api/nodes");
const node = nodes.find((n) => n.name.includes("Арасака")) ?? nodes[0];
const slots = await get("/api/slots");
const transfers = await get("/api/transfers");
const amounts = transfers.filter((t) => !t.cancelledAt).map((t) => t.amount).sort((a, b) => a - b);

// ── Chrome + DevTools ──
const chrome = spawn(CHROME, [
  "--headless=new", "--remote-debugging-port=9223", `--user-data-dir=${path.join(OUT, "profile")}`, `--window-size=${W},${H}`,
  "--hide-scrollbars", "--force-device-scale-factor=1", "--no-first-run", "--disable-gpu", "about:blank",
], { stdio: "ignore" });
process.on("exit", () => chrome.kill());

let target;
for (let i = 0; i < 50 && !target; i++) {
  try { target = (await (await fetch("http://127.0.0.1:9223/json/list")).json()).find((t) => t.type === "page"); } catch { /* ещё стартует */ }
  if (!target) await sleep(0.3);
}
if (!target) throw new Error("Chrome не запустился");

const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((r) => (ws.onopen = r));
let nextId = 1;
const pending = new Map();
const listeners = new Map();
ws.onmessage = (ev) => {
  const msg = JSON.parse(ev.data);
  if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); }
  else if (msg.method) (listeners.get(msg.method) ?? []).forEach((cb) => cb(msg.params));
};
const send = (method, params = {}) => new Promise((res, rej) => {
  const id = nextId++;
  pending.set(id, (m) => (m.error ? rej(new Error(`${method}: ${m.error.message}`)) : res(m.result)));
  ws.send(JSON.stringify({ id, method, params }));
});
const on = (method, cb) => listeners.set(method, [...(listeners.get(method) ?? []), cb]);
const evaluate = (expression) => send("Runtime.evaluate", { expression, awaitPromise: true, returnByValue: true });

await send("Page.enable");
await send("Emulation.setDeviceMetricsOverride", { width: W, height: H, deviceScaleFactor: 1, mobile: false });

// вход: кладём сессию в localStorage, как это делает форма входа
await send("Page.navigate", { url: `${API}/` });
await sleep(1.5);
await evaluate(`localStorage.setItem("mb10_admin_session", ${JSON.stringify(JSON.stringify(login))}); location.hash = "#/overview"; location.reload();`);
await sleep(2.5);

// ── запись кадров ──
const frames = [];
on("Page.screencastFrame", (p) => {
  const file = path.join(FRAMES, `f${String(frames.length).padStart(6, "0")}.jpg`);
  fs.writeFileSync(file, Buffer.from(p.data, "base64"));
  frames.push({ file, t: p.metadata.timestamp });
  send("Page.screencastFrameAck", { sessionId: p.sessionId }).catch(() => {});
});
await send("Page.startScreencast", { format: "jpeg", quality: 88, maxWidth: W, maxHeight: H, everyNthFrame: 1 });

// ── помощники сценария ──
const caption = (scene, text) => evaluate(`(() => {
  let el = document.getElementById("mb10-cap");
  if (!el) {
    el = document.createElement("div"); el.id = "mb10-cap";
    el.style.cssText = "position:fixed;left:0;right:0;bottom:0;z-index:99999;background:rgba(6,8,14,.93);border-top:2px solid #d9ff3f;padding:14px 28px;font:600 20px/1.35 -apple-system,Segoe UI,Roboto,sans-serif;color:#eaf2ff;";
    document.body.appendChild(el);
  }
  el.innerHTML = '<span style="color:#d9ff3f;letter-spacing:.06em;font-size:15px;display:block;margin-bottom:4px;">' + ${JSON.stringify(scene)} + '</span>' + ${JSON.stringify(text)};
})()`);
const go = async (hash) => { await evaluate(`location.hash = ${JSON.stringify(hash)}`); await sleep(1.6); };
const scroll = async (totalPx, seconds) => {
  const steps = Math.max(1, Math.round(seconds * 12));
  for (let i = 0; i < steps; i++) {
    await send("Input.dispatchMouseEvent", { type: "mouseWheel", x: W / 2, y: H / 2, deltaX: 0, deltaY: totalPx / steps });
    await sleep(seconds / steps);
  }
};
const title = (big, small) => evaluate(`(() => {
  const el = document.createElement("div"); el.id = "mb10-title";
  el.style.cssText = "position:fixed;inset:0;z-index:100000;background:#06080e;display:flex;flex-direction:column;align-items:center;justify-content:center;font-family:-apple-system,Segoe UI,Roboto,sans-serif;text-align:center;padding:40px;";
  el.innerHTML = '<div style="color:#d9ff3f;font-size:44px;font-weight:700;margin-bottom:18px;">' + ${JSON.stringify(big)} + '</div><div style="color:#eaf2ff;font-size:24px;max-width:900px;line-height:1.4;">' + ${JSON.stringify(small)} + '</div>';
  document.body.appendChild(el);
})()`);
const untitle = () => evaluate(`document.getElementById("mb10-title")?.remove()`);

// ── сценарий: порядок повторяет демо-ролик приложения ──
await title("Мегаблок №10 · панель мастера", "События из демо-ролика приложения, как их видит мастер: переводы, передача предметов, взлом узла, шард, сигнал СБ");
await sleep(5);
await untitle();

await go("#/overview");
await caption("СЦЕНА «ВЗЛОМ» · ОБЗОР",
  `Игроков на связи: ${overview.players.online} из ${overview.players.total}. Взломы за час (успех/частично/провал): ${overview.breachesLastHour.success}/${overview.breachesLastHour.partial}/${overview.breachesLastHour.fail}. ` +
  `Тиражных слотов в обороте: ${overview.slots.claimed} из ${overview.slots.printed}. Сигналы СБ: ушло ${overview.alerts.sent}, подавлено ${overview.alerts.suppressed} — демон Black Curtain сработал. Внизу живая лента: события приходят с телефонов сразу, по ним видно ход сцены.`);
await sleep(12);

await go("#/players");
await caption("ИГРОКИ", `Alice (Neon) и Bob (Rats): баланс, ёмкость буфера RAM, число демонов и шардов. Данные приходят с телефонов сами — мастер ничего не вводит.`);
await sleep(9);

await go(`#/players/${encodeURIComponent(alice.publicKeyB64)}`);
await caption("СЦЕНЫ «СДЕЛКА» → «ФИНАНСЫ» · ALICE",
  `Alice: эдди ${aliceSnap.balance}, RAM ${aliceSnap.ramCapacity}. Демоны: ${names(aliceSnap.daemons, "name")}. Шарды: ${names(aliceSnap.shards, "title")}. Счётчики взломов и подавленных сигналов СБ — выше.`);
await sleep(7);
await scroll(520, 4);
await caption("ALICE · ИСТОРИЯ ИЗМЕНЕНИЙ", "Новые записи сверху, читать снизу вверх: перевод 100 €$ от Bob → демон Black Curtain от Bob → взлом узла (успех, эдди, шард) → сигнал СБ подавлен → расшифровка шарда → шард уходит Bob → перевод 300 €$.");
await sleep(3);
await scroll(700, 8);
await sleep(6);

await go(`#/players/${encodeURIComponent(bob.publicKeyB64)}`);
await caption("BOB · ПРЕДМЕТЫ ПЕРЕДАЮТСЯ, А НЕ КОПИРУЮТСЯ", `Bob: эдди ${bobSnap.balance}. Демоны: ${names(bobSnap.daemons, "name")}. Шарды: ${names(bobSnap.shards, "title")}${bobSnap.shards.some((x) => x.decrypted) ? " (расшифрован)" : ""}. Демон ушёл к Alice, шард пришёл от неё — ни один предмет не размножился.`);
await sleep(8);
await scroll(500, 4);
await sleep(6);

await go("#/nodes");
await caption("СЦЕНА «ВЗЛОМ» · УЗЛЫ", `Узел «${node?.name ?? "Арасака-404"}» (${node?.tier ?? ""}): взломов — успех ${node?.breaches.success ?? 1}, уникальных игроков ${node?.uniquePlayers ?? 1}, сигналов СБ подавлено ${node?.alertsSuppressed ?? 1}.`);
await sleep(10);

await go("#/slots");
const claimed = slots.find((s) => s.copiesClaimed > 0);
await caption("РЕЕСТР ТИРАЖЕЙ", `Шард узла — тираж ${claimed?.copiesClaimed ?? 1} из ${claimed?.copiesTotal ?? 1}: слот забрал ${claimed?.claimants?.[0]?.claimantKeyB64 === alice.publicKeyB64 ? "Alice" : "один игрок"}, повторно его не забрать. Арбитраж идёт через сервер, дубликатов не будет; мастер может аннулировать заявку.`);
await sleep(10);

await go("#/transfers");
await caption("СЦЕНЫ «СДЕЛКА» И «ФИНАЛ» · ПЕРЕВОДЫ", `Переводы между игроками: ${amounts.join(" и ")} €$, оба подтверждены получателем (карточка доставлена → «Принять» → чек). Односторонних и отменённых нет.`);
await sleep(10);

await go("#/master");
await caption("МАСТЕРСКАЯ", "Так создан узел «Арасака-404»: генератор QR-меток контейнеров и шардов с шифрованной начинкой прямо в дашборде — игрок сканирует результат обычным сканером приложения.");
await sleep(9);

await title("Итог", "Мастер видит всё в реальном времени: деньги, предметы, взломы, тиражи и сигналы СБ — без ручного учёта на площадке.");
await sleep(5);

// ── завершение и сборка видео ──
await send("Page.stopScreencast");
await sleep(0.5);
ws.close();
chrome.kill();
if (frames.length < 2) throw new Error("screencast не дал кадров");

const lines = [];
frames.forEach((f, i) => {
  const dur = i < frames.length - 1 ? Math.max(0.04, frames[i + 1].t - f.t) : 3;
  lines.push(`file '${f.file}'`, `duration ${dur.toFixed(3)}`);
});
lines.push(`file '${frames[frames.length - 1].file}'`); // concat требует повторить последний кадр
fs.writeFileSync(path.join(OUT, "list.txt"), lines.join("\n"));
const out = path.join(OUT, "dashboard.mp4");
execFileSync("ffmpeg", ["-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", path.join(OUT, "list.txt"),
  "-vf", `fps=30,scale=${W}:${H},format=yuv420p`, "-c:v", "libx264", "-crf", "22", "-preset", "medium", "-movflags", "+faststart", out], { stdio: "inherit" });
const dur = execFileSync("ffprobe", ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", out]).toString().trim();
console.log(`${out}  ${dur} с, кадров screencast: ${frames.length}`);
