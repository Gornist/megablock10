#!/usr/bin/env node
// Одноразовый клиент Моста «Сети» для стенда e2e (scenarios/netrun-run.sh): подключается по WebSocket, делает hello с ролью
// (по умолчанию test — Мост запущен с --test), отправляет один запрос и печатает ответ одной строкой JSON. Без зависимостей (Node >= 22).
//   node netrun-bridge.mjs <порт Моста> <ключ роли> hello
//   node netrun-bridge.mjs <порт Моста> <ключ роли> '{"op":"get","type":"session","id":"s_…"}'
// Код возврата: 0 — Мост ответил (ok или нет, смотрите поле ok), 1 — не подключились / не дождались ответа за 15 с.
const [port, key, cmd] = process.argv.slice(2);
if (!port || !key || !cmd) { console.error("использование: netrun-bridge.mjs <порт> <ключ роли> hello|'<json запроса>'"); process.exit(2); }
const role = process.env.NETRUN_ROLE || "test";
const ws = new WebSocket(`ws://127.0.0.1:${port}/netrun/v1`);
const fail = (msg) => { console.error(`[netrun-bridge] ${msg}`); process.exit(1); };
const timer = setTimeout(() => fail("нет ответа за 15 с"), 15000);
let stage = "hello";
ws.onerror = () => fail("не подключиться к Мосту");
ws.onopen = () => ws.send(JSON.stringify({ v: 1, cid: "h", op: "hello", proto: 1, role, client: "e2e", key }));
ws.onmessage = (ev) => {
  const msg = JSON.parse(ev.data);
  if (msg.push) return;
  if (stage === "hello") {
    if (!msg.ok) fail(`hello отклонён: ${JSON.stringify(msg)}`);
    if (cmd === "hello") { console.log(JSON.stringify(msg)); process.exit(0); }
    stage = "req";
    ws.send(JSON.stringify({ v: 1, cid: "r", ...JSON.parse(cmd) }));
    return;
  }
  clearTimeout(timer);
  console.log(JSON.stringify(msg));
  process.exit(0);
};
