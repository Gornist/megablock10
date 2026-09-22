#!/usr/bin/env node
// Поддельное устройство игрока для сценариев-провокаторов (scripts/e2e/scenarios-anomaly): пара EC P-256, подписи ровно как у приложения
// (схема — admin-web/server/src/testUtil.ts) и POST /api/changes. Нужно там, где двух эмуляторов мало: «≥5 игроков на связи», подделки,
// чужие подписи, сбитые часы. Node ≥ 22 (встроенный fetch), без зависимостей.
//
//   node fakedev.mjs [--api URL] [--dir DIR] [--secret S] <команда> <имя> [опции]
//
//   register <имя> [--faction F] [--balance N] [--ram N] [--provision ID]
//                                                новичок: CHARACTER_CREATED (позывной, фракция, стартовый баланс); --provision — применить QR персонажа
//                                                с этим номером выдачи (sourceRef = ID, как делает приложение)
//   reset    <имя>                               сброс сессии: CHARACTER_RESET (позывной и фракция → пусто), как «Опасная зона» в приложении
//   beat     <имя> [--repeat N] [--pending N --oldest-ms N]
//                                                heartbeat (пустой батч); N — столько отдельных запросов подряд; --pending/--oldest-ms —
//                                                presence.pendingCount/oldestPendingAgeMs как в настоящем приложении (провокация sync_stuck)
//   send     <имя> --field F --reason R [--new V | --delta N] [--old V] [--ref ID] [--actor <имя|ключ>]
//                  [--bad-signature] [--happened-at +мс|абс] [--repeat N]
//                                                одна запись (или N записей одним батчем); для balance old берётся из состояния устройства
//   key      <имя>                               напечатать публичный ключ
//
// Состояние устройства (ключ, seq, баланс) лежит в DIR/<имя>.json — одно и то же «устройство» можно вызывать много раз.
// Вывод: одна строка JSON — что ответил сервер (accepted/rejected или status для не-200).
import { generateKeyPairSync, createPrivateKey, sign as cryptoSign, randomUUID } from "node:crypto";
import fs from "node:fs";
import path from "node:path";

const argv = process.argv.slice(2);
const opts = {};
const pos = [];
for (let i = 0; i < argv.length; i++) {
  const a = argv[i];
  if (a.startsWith("--")) {
    const key = a.slice(2);
    const next = argv[i + 1];
    if (next === undefined || next.startsWith("--")) opts[key] = true;
    else { opts[key] = next; i++; }
  } else pos.push(a);
}
const [cmd, name] = pos;
const API = opts.api ?? process.env.API ?? "http://localhost:2518";
const DIR = opts.dir ?? process.env.FAKE_DIR ?? "/tmp/mb10-fake";
const SECRET = opts.secret ?? process.env.GAME_SECRET;
if (!cmd || !name) { console.error("usage: fakedev.mjs <register|beat|send|key> <имя> [опции]"); process.exit(2); }
fs.mkdirSync(DIR, { recursive: true });

const stateFile = (n) => path.join(DIR, `${n}.json`);
function load(n) {
  const f = stateFile(n);
  if (fs.existsSync(f)) return JSON.parse(fs.readFileSync(f, "utf8"));
  const { publicKey, privateKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  return {
    name: n,
    publicKeyB64: publicKey.export({ type: "spki", format: "der" }).toString("base64"),
    privateKeyB64: privateKey.export({ type: "pkcs8", format: "der" }).toString("base64"),
    seq: 0,
    balance: 0,
  };
}
const save = (s) => fs.writeFileSync(stateFile(s.name), JSON.stringify(s));
const privateOf = (s) => createPrivateKey({ key: Buffer.from(s.privateKeyB64, "base64"), format: "der", type: "pkcs8" });

const payloadOf = (r) => Buffer.from([r.id, r.subjectKeyB64, String(r.seq), String(r.happenedAt), r.field, r.oldValue ?? "", r.newValue ?? "", r.reason, r.sourceRef ?? "", r.actor].join("|"), "utf8");

/** Собрать подписанную запись; signAs — подписать чужим ключом (для сценария подделки). */
function makeRecord(s, { field, oldValue = null, newValue, reason, sourceRef = null, actor, happenedAt, signAs }) {
  s.seq += 1;
  const rec = {
    id: randomUUID(), subjectKeyB64: s.publicKeyB64, seq: s.seq, happenedAt: happenedAt ?? Date.now(),
    field, oldValue, newValue, reason, sourceRef, actor: actor ?? s.publicKeyB64,
  };
  const key = signAs ? privateOf(signAs) : privateOf(s);
  return { ...rec, signature: cryptoSign("sha256", payloadOf(rec), { key, dsaEncoding: "der" }).toString("base64") };
}

async function post(body) {
  const headers = { "content-type": "application/json" };
  if (SECRET && SECRET !== "none") headers["x-game-secret"] = SECRET;
  const res = await fetch(`${API}/api/changes`, { method: "POST", headers, body: JSON.stringify(body) });
  let json = null;
  try { json = await res.json(); } catch { /* не JSON */ }
  return { status: res.status, json };
}
const summary = (r) => (r.status === 200 ? { status: 200, accepted: r.json?.accepted?.length ?? 0, rejected: r.json?.rejected ?? [] } : { status: r.status });

function actorKey(v) {
  if (v === undefined || v === true) return undefined;
  if (v.length > 40) return v;                      // уже ключ
  return load(v).publicKeyB64;                      // имя другого поддельного устройства (контрагент TRANSFER_IN)
}
function happenedAt(v) {
  if (v === undefined || v === true) return undefined;
  return String(v).startsWith("+") || String(v).startsWith("-") ? Date.now() + Number(v) : Number(v);
}

const s = load(name);

if (cmd === "key") {
  save(s);
  console.log(s.publicKeyB64);
} else if (cmd === "register") {
  const balance = Number(opts.balance ?? 100);
  const faction = String(opts.faction ?? "Neon");
  const ref = opts.provision && opts.provision !== true ? String(opts.provision) : null;
  s.faction = faction;
  const records = [
    makeRecord(s, { field: "callsign", oldValue: null, newValue: name, reason: "CHARACTER_CREATED", sourceRef: ref }),
    makeRecord(s, { field: "faction", oldValue: null, newValue: faction, reason: "CHARACTER_CREATED", sourceRef: ref }),
    makeRecord(s, { field: "balance", oldValue: null, newValue: String(balance), reason: "CHARACTER_CREATED", sourceRef: ref }),
  ];
  if (opts.ram !== undefined && opts.ram !== true) records.push(makeRecord(s, { field: "ramCapacity", oldValue: "6", newValue: String(opts.ram), reason: "CHARACTER_CREATED", sourceRef: ref }));
  const r = await post({ records, subjectKeyB64: s.publicKeyB64 });
  if (r.status === 200) { s.balance = balance; save(s); }
  console.log(JSON.stringify(summary(r)));
} else if (cmd === "reset") {
  const records = [
    makeRecord(s, { field: "callsign", oldValue: name, newValue: "", reason: "CHARACTER_RESET" }),
    makeRecord(s, { field: "faction", oldValue: s.faction ?? "", newValue: "", reason: "CHARACTER_RESET" }),
  ];
  const r = await post({ records, subjectKeyB64: s.publicKeyB64 });
  save(s);
  console.log(JSON.stringify(summary(r)));
} else if (cmd === "beat") {
  const n = Number(opts.repeat ?? 1);
  // --pending/--oldest-ms — то же поле presence, что шлёт настоящее приложение вместе с heartbeat (ChangeRecordStore.presenceJson):
  // не сама очередь на этом поддельном устройстве, а произвольные числа для сценариев sync_stuck (провокация без реальной очереди).
  const presence = opts.pending !== undefined || opts["oldest-ms"] !== undefined
    ? { pendingCount: Number(opts.pending ?? 0), oldestPendingAgeMs: Number(opts["oldest-ms"] ?? 0) }
    : undefined;
  let last = null;
  const statuses = {};
  for (let i = 0; i < n; i++) {
    last = await post({ records: [], subjectKeyB64: s.publicKeyB64, ...(presence ? { presence } : {}) });
    statuses[last.status] = (statuses[last.status] ?? 0) + 1;
  }
  console.log(JSON.stringify({ requests: n, statuses }));
} else if (cmd === "send") {
  const n = Number(opts.repeat ?? 1);
  const field = String(opts.field ?? "");
  const reason = String(opts.reason ?? "");
  if (!field || !reason) { console.error("нужны --field и --reason"); process.exit(2); }
  const bad = opts["bad-signature"] === true ? load("__forger__") : undefined;
  if (bad) save(bad);
  const records = [];
  let balance = s.balance;
  for (let i = 0; i < n; i++) {
    let oldValue = opts.old !== undefined && opts.old !== true ? String(opts.old) : field === "balance" ? String(balance) : null;
    let newValue;
    if (opts.new !== undefined && opts.new !== true) newValue = String(opts.new);
    else if (opts.delta !== undefined) newValue = String(balance + Number(opts.delta));
    else newValue = null;
    if (newValue === null) { console.error("нужен --new или --delta"); process.exit(2); }
    records.push(makeRecord(s, {
      field, oldValue, newValue, reason, sourceRef: opts.ref && opts.ref !== true ? String(opts.ref) : null,
      actor: actorKey(opts.actor), happenedAt: happenedAt(opts["happened-at"]), signAs: bad,
    }));
    if (field === "balance") balance = Number(newValue);
  }
  const r = await post({ records, subjectKeyB64: s.publicKeyB64 });
  if (r.status === 200 && !bad) { if (field === "balance") s.balance = balance; }
  save(s);
  console.log(JSON.stringify(summary(r)));
} else {
  console.error(`неизвестная команда: ${cmd}`);
  process.exit(2);
}
