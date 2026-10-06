#!/usr/bin/env node
// Одноразовый клиент Моста «Сети» для стенда e2e (scenarios/netrun-run.sh): подключается по WebSocket, делает hello с ролью
// (по умолчанию test — Мост запущен с --test), отправляет один запрос и печатает ответ одной строкой JSON. Без зависимостей (Node >= 22).
//   node netrun-bridge.mjs <порт Моста> <ключ роли> hello
//   node netrun-bridge.mjs <порт Моста> <ключ роли> '{"op":"get","type":"session","id":"s_…"}'
// Код возврата: 0 — Мост ответил (ok или нет, смотрите поле ok), 1 — не подключились / не дождались ответа.
// Мост на нагруженном раннере CI отвечает медленно (поезд #56, шаг «шард 2 остался в узле»: «нет ответа за 15 с» → пустой ответ → JSONDecodeError):
// ожидание — 30 с на попытку, а запросы только на чтение (hello, get, list) при тишине или обрыве повторяются один раз. Запись (всё остальное)
// не повторяем: потерянный ответ не значит, что Мост запрос не выполнил, и повтор мог бы выполнить его дважды.
const [port, key, cmd] = process.argv.slice(2);
if (!port || !key || !cmd) { console.error("использование: netrun-bridge.mjs <порт> <ключ роли> hello|'<json запроса>'"); process.exit(2); }
const role = process.env.NETRUN_ROLE || "test";
const fail = (msg) => { console.error(`[netrun-bridge] ${msg}`); process.exit(1); };

const TIMEOUT_MS = 30000;
const READ_OPS = new Set(["hello", "get", "list"]);
let request = null;
if (cmd !== "hello") {
  try { request = JSON.parse(cmd); } catch { console.error("[netrun-bridge] запрос — не JSON"); process.exit(2); }
}
const attempts = READ_OPS.has(request ? request.op : "hello") ? 2 : 1;

// Одна попытка: промис с ответом Моста на запрос; ошибка с fatal=true — повторять бессмысленно (hello отклонён).
const once = () => new Promise((resolve, reject) => {
  const ws = new WebSocket(`ws://127.0.0.1:${port}/netrun/v1`);
  let stage = "hello";
  const finish = (settle, value) => { clearTimeout(timer); try { ws.close(); } catch { /* уже закрыт */ } settle(value); };
  const timer = setTimeout(() => finish(reject, new Error(`нет ответа за ${TIMEOUT_MS / 1000} с`)), TIMEOUT_MS);
  ws.onerror = () => finish(reject, new Error("не подключиться к Мосту"));
  ws.onopen = () => ws.send(JSON.stringify({ v: 1, cid: "h", op: "hello", proto: 1, role, client: "e2e", key }));
  ws.onmessage = (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.push) return;
    if (stage === "hello") {
      if (!msg.ok) return finish(reject, Object.assign(new Error(`hello отклонён: ${JSON.stringify(msg)}`), { fatal: true }));
      if (!request) return finish(resolve, msg);
      stage = "req";
      ws.send(JSON.stringify({ v: 1, cid: "r", ...request }));
      return;
    }
    finish(resolve, msg);
  };
});

for (let i = 1; i <= attempts; i++) {
  try {
    console.log(JSON.stringify(await once()));
    process.exit(0);
  } catch (e) {
    if (e.fatal || i === attempts) fail(e.message);
    console.error(`[netrun-bridge] ${e.message} — повторяю запрос на чтение (${i}/${attempts})`);
  }
}
