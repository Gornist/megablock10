import { openDb } from "../db/index.js";
import { createMaster } from "../lib/auth.js";

/** npm run create-master -- <имя> — печатает выданный токен один раз, дальше он только в виде хэша в БД. */
const name = process.argv[2];
if (!name) {
  console.error("Использование: npm run create-master -- <имя мастера>");
  process.exit(1);
}

const db = openDb(process.env.DB_PATH ?? "./data/mb10-admin.sqlite");
const token = createMaster(db, name);
console.log(`Мастер "${name}" создан. Токен для входа (больше нигде не покажется):`);
console.log(token);
