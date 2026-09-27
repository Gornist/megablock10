import QRCode from "qrcode";

/**
 * Единственное место, где строка MB10-QR превращается в матрицу модулей: картинка для печати и экрана ноутбука (qrImageDataUrl)
 * и кадр для электронного дисплея (displays/renderer.ts) строятся из одной и той же матрицы, с одним уровнем коррекции ошибок.
 * Раньше опции { margin: 1, width: 480 } были переписаны в четырёх роутах — второй генератор «для дисплеев» рядом с ними
 * разошёлся бы с печатью незаметно.
 */
export const QR_ERROR_CORRECTION = "M" as const;

export interface QrMatrix {
  /** Модулей по стороне (без тихой зоны). */
  size: number;
  /** Версия QR (1–40): чем длиннее строка, тем больше модулей. */
  version: number;
  /** true — тёмный модуль. */
  dark(row: number, col: number): boolean;
}

export function qrMatrix(text: string): QrMatrix {
  const qr = QRCode.create(text, { errorCorrectionLevel: QR_ERROR_CORRECTION });
  const { size } = qr.modules;
  return { size, version: qr.version, dark: (row, col) => qr.modules.get(row, col) === 1 };
}

/** PNG для печати/показа с экрана — тот же QR, что уходит на дисплей. */
export function qrImageDataUrl(text: string): Promise<string> {
  return QRCode.toDataURL(text, { errorCorrectionLevel: QR_ERROR_CORRECTION, margin: 1, width: 480 });
}
