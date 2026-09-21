import { test } from "node:test";
import assert from "node:assert/strict";
import { productionProblems } from "./lib/productionMode.js";
import { testDb, testMaster } from "./testUtil.js";

test("обычный режим ничего не требует", () => {
  assert.deepEqual(productionProblems(testDb(), {}), []);
  assert.deepEqual(productionProblems(testDb(), { MB10_MODE: "dev" }), []);
});

test("боевой режим: нужны секрет игры и мастер", () => {
  const db = testDb();
  const env = { MB10_MODE: "production" };
  assert.equal(productionProblems(db, env).length, 2);
  assert.match(productionProblems(db, { ...env, GAME_SECRET: "long-enough-secret" }).join(), /нет ни одного мастера/);

  testMaster(db, "Мастер-1");
  assert.deepEqual(productionProblems(db, { ...env, GAME_SECRET: "long-enough-secret" }), []);
});

test("боевой режим: короткий секрет и заглушка из юнита не проходят", () => {
  const db = testDb();
  testMaster(db, "Мастер-1");
  assert.match(productionProblems(db, { MB10_MODE: "PRODUCTION", GAME_SECRET: "short" }).join(), /короче/);
  assert.match(productionProblems(db, { MB10_MODE: "production", GAME_SECRET: "замени-на-свою-строку" }).join(), /заглушкой/);
});
