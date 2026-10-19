import { test } from "node:test";
import assert from "node:assert/strict";
import { PROVISION_CODE_ALPHABET, PROVISION_CODE_LENGTH, formatProvisionCode, isProvisionCode, normalizeProvisionCode } from "./lib/provisionCode.js";
import { loadContract } from "./contractVectors.js";

/**
 * Короткий код персонажа против общих векторов `provision-code.json` (их же читает приложение): алфавит, длина, нормализация ввода и
 * показ «ABC-DEF». Телефон нормализует до отправки, сервер — так же; расхождение жгло бы попытки или не пускало бы игрока.
 */
interface ProvisionCodeVectors {
  alphabet: string;
  length: number;
  normalize: { name: string; input: string; output: string | null }[];
  format: { code: string; text: string }[];
}
const v = loadContract<ProvisionCodeVectors>("provision-code");

test("алфавит и длина кода как в векторах", () => {
  assert.equal(PROVISION_CODE_ALPHABET, v.alphabet);
  assert.equal(PROVISION_CODE_LENGTH, v.length);
});

for (const c of v.normalize) {
  test(`нормализация: ${c.name}`, () => {
    const normalized = normalizeProvisionCode(c.input);
    // null в векторах — «не код»: сервер даёт на это 404 и неверную попытку
    assert.equal(isProvisionCode(normalized) ? normalized : null, c.output);
  });
}

for (const f of v.format) {
  test(`показ: ${f.code} → ${f.text}`, () => {
    assert.equal(formatProvisionCode(f.code), f.text);
  });
}
