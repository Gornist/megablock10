import { randomInt } from "node:crypto";

/**
 * Короткий код выдачи персонажа (решение владельца 19.10: ввод кода без камеры — «короткий идентификатор, не сложный, не подбираемый»).
 * 6 знаков из 31: A–Z без O, I, L и 2–9 (без 0, 1 и похожих) — 31^6 ≈ 887 млн вариантов. Телефон меняет его на ту же строку QR
 * через POST /api/provisions/redeem; защита от подбора — redeemLimiter.ts. Алфавит и нормализация сверяются общими векторами
 * `provision-code.json` (rules/src/test/resources/contracts/).
 */
export const PROVISION_CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
export const PROVISION_CODE_LENGTH = 6;

/** Криптослучайный код из 6 знаков алфавита. Уникальность среди непогашенных — забота вызывающего (createProvision). */
export function generateProvisionCode(): string {
  let code = "";
  for (let i = 0; i < PROVISION_CODE_LENGTH; i++) code += PROVISION_CODE_ALPHABET[randomInt(PROVISION_CODE_ALPHABET.length)];
  return code;
}

/** Ввод человека → хранимая форма: верхний регистр, без пробелов и тире. Валидность не проверяет — см. isProvisionCode. */
export function normalizeProvisionCode(input: string): string {
  return input.toUpperCase().replace(/[\s-]/g, "");
}

export function isProvisionCode(normalized: string): boolean {
  return normalized.length === PROVISION_CODE_LENGTH && [...normalized].every((c) => PROVISION_CODE_ALPHABET.includes(c));
}

/** Вид для мастера: «ABC-DEF» (при вводе тире не важно). */
export function formatProvisionCode(code: string): string {
  return `${code.slice(0, 3)}-${code.slice(3)}`;
}
