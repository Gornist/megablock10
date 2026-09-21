import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { buildApp } from "./app.js";
import { openDb } from "./db/index.js";
import { scheduleBackups } from "./lib/backup.js";
import { EXIT_CONFIG, isProduction, productionProblems } from "./lib/productionMode.js";

const PORT = Number(process.env.PORT ?? 2517);
const DB_PATH = process.env.DB_PATH ?? "./data/mb10-admin.sqlite";
const BACKUP_DIR = process.env.BACKUP_DIR ?? "./data/backups";
const BACKUP_INTERVAL_MS = Number(process.env.BACKUP_INTERVAL_MS ?? 30 * 60 * 1000);

const db = openDb(DB_PATH);

// MB10_MODE=production: не стартовать «открытым» по недосмотру (без секрета игры или без мастера).
const problems = productionProblems(db);
if (problems.length > 0) {
  console.error(`Боевой режим (MB10_MODE=production): запуск отменён.\n - ${problems.join("\n - ")}`);
  process.exit(EXIT_CONFIG);
}
if (isProduction()) console.log("Боевой режим: секрет игры и мастер на месте.");

const clientDist = join(dirname(fileURLToPath(import.meta.url)), "../../client/dist");
const app = buildApp(db, { clientDist });

// На :memory: (тестовый режим buildApp не используется тут вовсе) бэкапить
// нечего и некуда — в реальном запуске DB_PATH всегда файл на диске.
scheduleBackups(db, BACKUP_DIR, BACKUP_INTERVAL_MS);

app.listen({ port: PORT, host: "0.0.0.0" }).catch((err) => {
  app.log.error(err);
  process.exit(1);
});
