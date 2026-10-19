import { test, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { seedPlayer, setup, type App, type Device } from "./testHelpers.js";
import { testDevice } from "./testUtil.js";
import { PROVISION_CODE_ALPHABET, formatProvisionCode, generateProvisionCode, isProvisionCode, normalizeProvisionCode } from "./lib/provisionCode.js";
import { REDEEM_GLOBAL_WINDOW_MS, REDEEM_IP_FAILS, REDEEM_IP_PAUSE_MS, createRedeemLimiter, redeemLimiter } from "./lib/redeemLimiter.js";
import { CAPABILITIES } from "./routes/capabilities.js";

/**
 * Вход коротким кодом без камеры (решение владельца 19.10): код при выдаче, обмен на строку QR без мастера, защита от подбора.
 * Одноразовость по-прежнему держит bindProvision при применении — обмен кода его не гасит.
 */
type Prov = { item: { id: string; code: string | null; void: boolean }; qr: string };
type Item = { kind: string };

const send = (app: App, ...records: unknown[]) => app.inject({ method: "POST", url: "/api/changes", payload: { records } });
const redeem = (app: App, code: unknown, ip?: string) =>
  app.inject({ method: "POST", url: "/api/provisions/redeem", payload: { code }, ...(ip ? { remoteAddress: ip } : {}) });

async function issue(app: App, headers: Record<string, string>, callsign = "Alice") {
  const res = await app.inject({ method: "POST", url: "/api/provisions", headers, payload: { callsign, faction: "Neon", balance: 500, ram: 8 } });
  assert.equal(res.statusCode, 200, res.body);
  return res.json() as Prov;
}

const applyCode = (d: Device, id: string) => [
  d.change({ field: "callsign", newValue: "Alice", reason: "CHARACTER_CREATED", sourceRef: id }),
  d.change({ field: "faction", newValue: "Neon", reason: "CHARACTER_CREATED", sourceRef: id }),
  d.change({ field: "ramCapacity", oldValue: "6", newValue: "8", reason: "CHARACTER_CREATED", sourceRef: id }),
  d.change({ field: "balance", oldValue: "0", newValue: "500", reason: "CHARACTER_CREATED", sourceRef: id }),
];

const plain = (display: string | null) => display!.replace("-", "");

beforeEach(() => redeemLimiter.reset());

test("алфавит: 31 знак, без O I L и без 0 1; код — 6 знаков алфавита; нормализация и показ", () => {
  assert.equal(PROVISION_CODE_ALPHABET.length, 31);
  assert.equal(new Set(PROVISION_CODE_ALPHABET).size, 31);
  for (const bad of "OIL01") assert.ok(!PROVISION_CODE_ALPHABET.includes(bad), bad);
  for (let i = 0; i < 500; i++) assert.ok(isProvisionCode(generateProvisionCode()));
  assert.equal(normalizeProvisionCode(" abc-def "), "ABCDEF");
  assert.equal(normalizeProvisionCode("a-b c-d e-f"), "ABCDEF");
  assert.equal(formatProvisionCode("ABCDEF"), "ABC-DEF");
  for (const bad of ["", "ABCDE", "ABCDEFG", "ABCDE0", "ABCDEO", "ABCDEI", "ABCDEL", "ABCDE1", "abcdef", "ABC-DEF"]) assert.ok(!isProvisionCode(bad), bad);
});

test("capabilities объявляет provisionCode: 1", () => {
  assert.equal(CAPABILITIES.provisionCode, 1);
});

test("выдача: у каждой выдачи свой код вида ABC-DEF; мастеру он виден в списке; обмен без мастера отдаёт ту же строку QR", async () => {
  const { app, headers } = await setup();
  const a = await issue(app, headers, "Alice");
  const b = await issue(app, headers, "Bob");
  assert.match(a.item.code!, /^[A-Z2-9]{3}-[A-Z2-9]{3}$/);
  assert.notEqual(a.item.code, b.item.code);

  const list = (await app.inject({ method: "GET", url: "/api/provisions", headers })).json().items as { id: string; code: string | null }[];
  assert.equal(list.find((p) => p.id === a.item.id)!.code, a.item.code);

  // ввод человека: строчные, без тире, с пробелами — всё равно тот же код
  for (const typed of [plain(a.item.code), a.item.code!.toLowerCase(), ` ${a.item.code} `]) {
    const res = await redeem(app, typed);
    assert.equal(res.statusCode, 200, res.body);
    assert.deepEqual(res.json(), { qr: a.qr }, "ровно строка из GET /api/provisions/:id/qr");
  }
  assert.equal(((await app.inject({ method: "GET", url: `/api/provisions/${a.item.id}/qr`, headers })).json() as Prov).qr, a.qr);
});

test("обмен не гасит код (повтор до применения допустим); применение гасит: после bindProvision код — как неизвестный", async () => {
  const { app, headers } = await setup();
  const p = await issue(app, headers);
  assert.equal((await redeem(app, p.item.code)).statusCode, 200);
  assert.equal((await redeem(app, p.item.code)).statusCode, 200);

  const phone = testDevice();
  assert.deepEqual((await send(app, ...applyCode(phone, p.item.id))).json().rejected, []);
  const res = await redeem(app, p.item.code);
  assert.equal(res.statusCode, 404);
  assert.deepEqual(res.json(), { error: "unknown_code" });
  const item = ((await app.inject({ method: "GET", url: "/api/provisions", headers })).json().items as { id: string; code: string | null }[]).find((x) => x.id === p.item.id)!;
  assert.equal(item.code, null, "применённой выдаче код в списке не показываем");
});

test("перевыдача гасит прежний код: старый — 404 (так же, как неизвестный), новый — открывается", async () => {
  const { app, headers } = await setup();
  const alice = await seedPlayer(app, { callsign: "Alice", faction: "Neon", balance: 100 });
  const first = await app.inject({ method: "POST", url: `/api/players/${encodeURIComponent(alice.publicKeyB64)}/reissue`, headers, payload: {} });
  const second = await app.inject({ method: "POST", url: `/api/players/${encodeURIComponent(alice.publicKeyB64)}/reissue`, headers, payload: {} });
  const a = first.json() as Prov;
  const b = second.json() as Prov;
  assert.equal((await redeem(app, a.item.code)).statusCode, 404, "первая перевыдача погашена второй");
  assert.deepEqual((await redeem(app, b.item.code)).json(), { qr: b.qr });
});

test("неизвестный код, мусор, не тот алфавит и пустой — 404 unknown_code; не строка — 400", async () => {
  const { app } = await setup();
  for (const code of ["ABCDEF", "ZZZ-ZZZ", "AB", "ABCDEFGH", "OOOOOO", "000000", "", "ABC DEF!"]) {
    const res = await redeem(app, code);
    assert.equal(res.statusCode, 404, code);
    assert.deepEqual(res.json(), { error: "unknown_code" });
    redeemLimiter.reset();
  }
  assert.equal((await redeem(app, 123456)).statusCode, 400);
  assert.equal((await redeem(app, undefined)).statusCode, 400);
  assert.equal((await redeem(app, "A".repeat(65))).statusCode, 400);
});

test("5 неверных подряд с одного IP — 429 с retryAfterSec; верный код в паузе тоже 429 (подсказки нет); другой IP не затронут", async () => {
  const { app, headers } = await setup();
  const p = await issue(app, headers);
  for (let i = 0; i < REDEEM_IP_FAILS; i++) assert.equal((await redeem(app, "ZZZZZZ", "10.10.0.5")).statusCode, 404);

  const blocked = await redeem(app, "ZZZZZZ", "10.10.0.5");
  assert.equal(blocked.statusCode, 429);
  const body = blocked.json() as { error: string; retryAfterSec: number };
  assert.equal(body.error, "rate_limited");
  assert.ok(body.retryAfterSec > 0 && body.retryAfterSec <= REDEEM_IP_PAUSE_MS / 1000, String(body.retryAfterSec));
  assert.equal(blocked.headers["retry-after"], String(body.retryAfterSec));

  assert.equal((await redeem(app, p.item.code, "10.10.0.5")).statusCode, 429, "верный код в паузе не проверяется");
  assert.equal((await redeem(app, p.item.code, "10.10.0.6")).statusCode, 200, "другой IP работает");
});

test("верный код сбрасывает счётчик неверных этого IP", async () => {
  const { app, headers } = await setup();
  const p = await issue(app, headers);
  for (let round = 0; round < 3; round++) {
    for (let i = 0; i < REDEEM_IP_FAILS - 1; i++) assert.equal((await redeem(app, "ZZZZZZ", "10.10.0.7")).statusCode, 404);
    assert.equal((await redeem(app, p.item.code, "10.10.0.7")).statusCode, 200);
  }
});

test("лимитер: пауза IP заканчивается через 5 минут и снова даёт 5 попыток", () => {
  const l = createRedeemLimiter(100);
  const t0 = 1_000_000;
  for (let i = 0; i < REDEEM_IP_FAILS; i++) l.fail("a", t0);
  const gate = l.check("a", t0 + 1000);
  assert.ok(!gate.ok && gate.scope === "ip" && gate.retryAfterSec === REDEEM_IP_PAUSE_MS / 1000 - 1);
  assert.deepEqual(l.check("a", t0 + REDEEM_IP_PAUSE_MS), { ok: true });
  for (let i = 0; i < REDEEM_IP_FAILS - 1; i++) l.fail("a", t0 + REDEEM_IP_PAUSE_MS);
  assert.deepEqual(l.check("a", t0 + REDEEM_IP_PAUSE_MS), { ok: true }, "после паузы счёт начался заново: 4 неверных — ещё не пауза");
  l.fail("a", t0 + REDEEM_IP_PAUSE_MS);
  assert.ok(!l.check("a", t0 + REDEEM_IP_PAUSE_MS).ok, "пятая — снова пауза");
});

test("лимитер: общий потолок неверных в час — на весь сервер, блокирует новый IP и сходит через час после первой неверной", () => {
  const l = createRedeemLimiter(8);
  const t0 = 1_000_000;
  for (let i = 0; i < 8; i++) l.fail(`ip${i}`, t0 + i); // по одной с восьми адресов — до IP-паузы далеко
  const g = l.check("новый", t0 + 10);
  assert.ok(!g.ok && g.scope === "global");
  assert.equal(l.globalBlockedAt(t0 + 10), t0 + 10);
  assert.deepEqual(l.check("новый", t0 + REDEEM_GLOBAL_WINDOW_MS + 8), { ok: true }, "через час все восемь вышли из окна");
  assert.equal(l.globalBlockedAt(t0 + 10 + REDEEM_GLOBAL_WINDOW_MS), null, "тревога тоже гаснет через час");
});

test("общий потолок блокирует всех и поднимает тревогу мастеру «Перебор коротких кодов»", async () => {
  const { app, headers } = await setup();
  const p = await issue(app, headers);
  const attention = async () => (await app.inject({ method: "GET", url: "/api/attention", headers })).json().items as Item[];
  assert.ok(!(await attention()).some((i) => i.kind === "redeem_flood"));

  for (let i = 0; i < 100; i++) redeemLimiter.fail(`10.20.${i >> 8}.${i & 255}`); // сто разных IP — каждый по одной неверной
  const res = await redeem(app, p.item.code, "10.10.0.9");
  assert.equal(res.statusCode, 429);
  assert.ok((res.json() as { retryAfterSec: number }).retryAfterSec > 0);
  assert.ok((await attention()).some((i) => i.kind === "redeem_flood"));
});

test("уникальность среди непогашенных: два открытых с одним кодом невозможны, у погашенных код можно использовать снова", async () => {
  const { app, headers, db } = await setup();
  const a = await issue(app, headers, "Alice");
  const b = await issue(app, headers, "Bob");
  const codeOf = (id: string) => (db.prepare(`SELECT short_code FROM provisions WHERE id = ?`).get(id) as { short_code: string }).short_code;
  assert.throws(() => db.prepare(`UPDATE provisions SET short_code = ? WHERE id = ?`).run(codeOf(a.item.id), b.item.id), /UNIQUE/);
  db.prepare(`UPDATE provisions SET void = 1 WHERE id = ?`).run(a.item.id);
  db.prepare(`UPDATE provisions SET short_code = ? WHERE id = ?`).run(codeOf(a.item.id), b.item.id); // не бросает: у a код уже погашен
  assert.equal(codeOf(b.item.id), codeOf(a.item.id));
});
