import type { Db } from "../db/index.js";

export const MIN_GAME_SECRET_LENGTH = 8;
/** Код выхода «неверная конфигурация» (EX_CONFIG): systemd-юнит по нему не перезапускает процесс впустую. */
/** Заглушка из deploy/mb10-admin.service: забытая замена не должна проходить как настоящий секрет. */
const PLACEHOLDER_SECRET = "замени-на-свою-строку";
export const EXIT_CONFIG = 78;

export function isProduction(env: NodeJS.ProcessEnv = process.env): boolean {
  return (env.MB10_MODE ?? "").toLowerCase() === "production";
}

/**
 * Проверки запуска боевого режима (MB10_MODE=production): без секрета игры
 * любое устройство в сети может сыпать в /api/changes, а без мастера в базе
 * дашборд просто недоступен. В обычном режиме (разработка, тесты) ничего не
 * требуется — возвращается пустой список. Возвращает человекочитаемые проблемы.
 */
export function productionProblems(db: Db, env: NodeJS.ProcessEnv = process.env): string[] {
  if (!isProduction(env)) return [];
  const problems: string[] = [];
  const secret = env.GAME_SECRET ?? "";
  if (!secret) problems.push("не задан GAME_SECRET (общий секрет игры для устройств)");
  else if (secret === PLACEHOLDER_SECRET) problems.push("GAME_SECRET остался заглушкой из systemd-юнита");
  else if (secret.length < MIN_GAME_SECRET_LENGTH) problems.push(`GAME_SECRET короче ${MIN_GAME_SECRET_LENGTH} символов`);
  const masters = (db.prepare(`SELECT COUNT(*) AS n FROM masters`).get() as { n: number }).n;
  if (masters === 0) problems.push("в базе нет ни одного мастера (npm run create-master -- \"Имя\")");
  return problems;
}
