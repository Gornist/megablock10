/**
 * Разбор WAV объявления (docs/sound-nodes.md, «Громкая связь»): коллектор записывает клип в браузере и кодирует в IMA ADPCM
 * (формат 0x11, моно, 16 кГц, ≈ 8 КБ/с) — точка декодирует его без библиотек. Сервер проверяет формат и узнаёт длительность.
 */
export interface WavInfo {
  /** 1 — PCM, 0x11 — IMA ADPCM. */
  format: number;
  channels: number;
  sampleRate: number;
  bitsPerSample: number;
  blockAlign: number;
  /** IMA ADPCM: сэмплов в блоке. */
  samplesPerBlock: number;
  dataOffset: number;
  dataBytes: number;
  durationMs: number;
}

export const WAV_PCM = 1;
export const WAV_IMA_ADPCM = 0x11;

/** null — не WAV или формат, который точка не сыграет (нужен PCM 16 бит или IMA ADPCM 4 бит, моно). */
export function parseWav(buf: Buffer): WavInfo | null {
  if (buf.length < 44 || buf.toString("ascii", 0, 4) !== "RIFF" || buf.toString("ascii", 8, 12) !== "WAVE") return null;
  let off = 12;
  let fmt: Omit<WavInfo, "dataOffset" | "dataBytes" | "durationMs"> | null = null;
  while (off + 8 <= buf.length) {
    const id = buf.toString("ascii", off, off + 4);
    const size = buf.readUInt32LE(off + 4);
    const body = off + 8;
    if (id === "fmt " && size >= 16 && body + size <= buf.length) {
      const format = buf.readUInt16LE(body);
      fmt = {
        format,
        channels: buf.readUInt16LE(body + 2),
        sampleRate: buf.readUInt32LE(body + 4),
        blockAlign: buf.readUInt16LE(body + 12),
        bitsPerSample: buf.readUInt16LE(body + 14),
        samplesPerBlock: format === WAV_IMA_ADPCM && size >= 20 ? buf.readUInt16LE(body + 18) : 1,
      };
    } else if (id === "data" && fmt) {
      const dataBytes = Math.min(size, buf.length - body);
      const ok =
        fmt.channels === 1 &&
        fmt.sampleRate >= 8000 &&
        fmt.sampleRate <= 48000 &&
        ((fmt.format === WAV_PCM && fmt.bitsPerSample === 16) || (fmt.format === WAV_IMA_ADPCM && fmt.bitsPerSample === 4 && fmt.blockAlign > 4));
      if (!ok) return null;
      const samples = fmt.format === WAV_PCM ? dataBytes / 2 : Math.floor(dataBytes / fmt.blockAlign) * fmt.samplesPerBlock;
      return { ...fmt, dataOffset: body, dataBytes, durationMs: Math.round((samples / fmt.sampleRate) * 1000) };
    }
    off = body + size + (size & 1);
  }
  return null;
}
