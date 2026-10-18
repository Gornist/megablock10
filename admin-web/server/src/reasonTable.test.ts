import { test } from "node:test";
import assert from "node:assert/strict";
import { REASONS, REASON_INFO, reasonInfo, rewardReasonsSql } from "./lib/changeRecord.js";
import { REASON_LABEL_RU } from "./lib/humanize.js";

/**
 * Таблица причин записей (changeRecord.ts, REASON_INFO) заменила пять отдельных списков в integrity/anomalies/pulse/analytics/humanize.
 * Эти тесты фиксируют ПРЕЖНЕЕ содержимое списков: правка признака причины — осознанное решение с правкой теста, а не побочный эффект.
 */
const codesWhere = (flag: "gainsBalance" | "reward" | "transfer") => REASONS.filter((c) => REASON_INFO[c][flag]).sort();

test("баланс законно растёт: награды, получение и возврат перевода, правка мастера, старт и сброс персонажа", () => {
  assert.deepEqual(codesWhere("gainsBalance"), [
    "BREACH_EDDIES", "BREACH_LOOT", "CHARACTER_CREATED", "CHARACTER_RESET", "MASTER_OVERRIDE", "SHARD_SCAN", "TRANSFER_CANCELLED", "TRANSFER_IN",
  ]);
});

test("награды за игру: эдди за взлом, добыча, скан шарда — и они же законно прибавляют баланс", () => {
  assert.deepEqual(codesWhere("reward"), ["BREACH_EDDIES", "BREACH_LOOT", "SHARD_SCAN"]);
  for (const c of REASONS) if (REASON_INFO[c].reward) assert.ok(REASON_INFO[c].gainsBalance, `${c}: награда обязана быть законным приростом`);
  assert.equal(rewardReasonsSql(), "'BREACH_LOOT','BREACH_EDDIES','SHARD_SCAN'", "тот же список уходит в SQL выбросов");
});

test("переводы между игроками: отправка, получение, отмена — не источник эмиссии", () => {
  assert.deepEqual(codesWhere("transfer"), ["TRANSFER_CANCELLED", "TRANSFER_IN", "TRANSFER_OUT"]);
});

test("у каждой причины есть подпись, словарь подписей собран из той же таблицы; неизвестный код — null, а не свойство Object", () => {
  for (const c of REASONS) {
    assert.ok(REASON_INFO[c].label.length > 0, c);
    assert.equal(REASON_LABEL_RU[c], REASON_INFO[c].label);
  }
  assert.equal(reasonInfo("NO_SUCH_REASON"), null);
  assert.equal(reasonInfo("constructor"), null);
  assert.equal(reasonInfo("TRANSFER_IN")?.gainsBalance, true);
});
