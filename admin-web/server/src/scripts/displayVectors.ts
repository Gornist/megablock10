import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { protocolVectorsJson, VECTORS_PATH_FROM_SERVER } from "../displays/vectors.js";

/** Переписать общие тестовые векторы протокола дисплеев (firmware/display/test/vectors/protocol-v1.json) после правки protocol.ts. */
const path = join(dirname(fileURLToPath(import.meta.url)), "../..", VECTORS_PATH_FROM_SERVER);
writeFileSync(path, protocolVectorsJson());
console.log(`written ${path}`);
