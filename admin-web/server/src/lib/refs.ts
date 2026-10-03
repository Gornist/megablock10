/** Общие проверки идентификаторов и целых из тела запроса: документы Моста («Сеть»), события мира, аудио, точки. */

/** Идентификатор документа Моста / узла / предмета: буквы, цифры, `_ . : -`, до 64 знаков. */
export const REF = /^[A-Za-z0-9_.:-]{1,64}$/;
/** То же, но до 100 знаков — привязки точек к узлам и терминалам, поля событий мира. */
export const REF_LONG = /^[A-Za-z0-9_.:-]{1,100}$/;

export const isRef = (v: unknown): v is string => typeof v === "string" && REF.test(v);

/** Целое число в [min, max] включительно. */
export const isIntIn = (v: unknown, min: number, max: number): v is number => Number.isInteger(v) && (v as number) >= min && (v as number) <= max;
