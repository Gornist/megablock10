/**
 * Типы ответов API — ЕДИНСТВЕННОЕ описание формы данных между сервером и
 * дашбордом. Сервер аннотирует ими то, что отдаёт, клиент (client/src/api/types.ts)
 * импортирует их отсюда, так что расхождение ловит компилятор, а не мастер на
 * живой игре. Файл только для типов: никаких значений — клиент собирается
 * отдельно и не должен тянуть серверный код. Описания разложены по доменам в
 * каталоге types/, здесь — баррель, чтобы импорты `apiTypes` не менялись.
 */

export type * from "./types/events.js";
export type * from "./types/players.js";
export type * from "./types/nodes.js";
export type * from "./types/analytics.js";
export type * from "./types/audit.js";
export type * from "./types/displays.js";
export type * from "./types/audio.js";
export type * from "./types/netAccess.js";
export type * from "./types/worldEvents.js";
export type * from "./types/netState.js";
