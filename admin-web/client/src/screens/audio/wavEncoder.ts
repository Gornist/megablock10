/**
 * Клип громкой связи в формате, который точка играет без библиотек (docs/sound-nodes.md): WAV IMA ADPCM, моно, 16 кГц,
 * блок 256 байт = 505 сэмплов, ≈ 8 КБ/с — 10-секундное объявление ≈ 80 КБ, по Wi-Fi точки это доли секунды.
 */
export const CLIP_RATE = 16000;
const BLOCK_ALIGN = 256;
export const SAMPLES_PER_BLOCK = (BLOCK_ALIGN - 4) * 2 + 1;

const STEPS = [
  7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130, 143, 157, 173, 190, 209, 230, 253,
  279, 307, 337, 371, 408, 449, 494, 544, 598, 658, 724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327, 3660,
  4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899, 15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767,
];
const INDEX_ADJUST = [-1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8];

const clamp = (v: number, lo: number, hi: number) => (v < lo ? lo : v > hi ? hi : v);

/** Float [-1..1] → IMA ADPCM WAV. */
export function encodeImaAdpcmWav(samples: Float32Array, rate = CLIP_RATE): Uint8Array {
  const blocks = Math.max(1, Math.ceil(samples.length / SAMPLES_PER_BLOCK));
  const dataBytes = blocks * BLOCK_ALIGN;
  const headerBytes = 12 + 8 + 20 + 12 + 8;
  const out = new Uint8Array(headerBytes + dataBytes);
  const v = new DataView(out.buffer);
  const ascii = (off: number, s: string) => [...s].forEach((c, i) => (out[off + i] = c.charCodeAt(0)));
  ascii(0, "RIFF");
  v.setUint32(4, out.length - 8, true);
  ascii(8, "WAVE");
  ascii(12, "fmt ");
  v.setUint32(16, 20, true);
  v.setUint16(20, 0x11, true);
  v.setUint16(22, 1, true);
  v.setUint32(24, rate, true);
  v.setUint32(28, Math.round((rate * BLOCK_ALIGN) / SAMPLES_PER_BLOCK), true);
  v.setUint16(32, BLOCK_ALIGN, true);
  v.setUint16(34, 4, true);
  v.setUint16(36, 2, true);
  v.setUint16(38, SAMPLES_PER_BLOCK, true);
  ascii(40, "fact");
  v.setUint32(44, 4, true);
  v.setUint32(48, samples.length, true);
  ascii(52, "data");
  v.setUint32(56, dataBytes, true);

  const pcm = (i: number) => (i < samples.length ? clamp(Math.round(samples[i] * 32767), -32768, 32767) : 0);
  let index = 0;
  for (let b = 0; b < blocks; b++) {
    const base = b * SAMPLES_PER_BLOCK;
    const off = headerBytes + b * BLOCK_ALIGN;
    let pred = pcm(base);
    v.setInt16(off, pred, true);
    out[off + 2] = index;
    out[off + 3] = 0;
    for (let k = 1; k < SAMPLES_PER_BLOCK; k++) {
      let diff = pcm(base + k) - pred;
      let code = 0;
      if (diff < 0) {
        code = 8;
        diff = -diff;
      }
      let step = STEPS[index];
      let delta = step >> 3;
      if (diff >= step) {
        code |= 4;
        diff -= step;
        delta += step;
      }
      step >>= 1;
      if (diff >= step) {
        code |= 2;
        diff -= step;
        delta += step;
      }
      step >>= 1;
      if (diff >= step) {
        code |= 1;
        delta += step;
      }
      pred = clamp(code & 8 ? pred - delta : pred + delta, -32768, 32767);
      index = clamp(index + INDEX_ADJUST[code], 0, 88);
      const byte = off + 4 + ((k - 1) >> 1);
      out[byte] |= (k - 1) & 1 ? code << 4 : code;
    }
  }
  return out;
}

/** Обратное — для тестов и проверки на слух; та же таблица, что в прошивке. */
export function decodeImaAdpcm(wav: Uint8Array): Int16Array {
  const v = new DataView(wav.buffer, wav.byteOffset, wav.byteLength);
  const total = v.getUint32(48, true);
  const dataBytes = v.getUint32(56, true);
  const out = new Int16Array(total);
  let n = 0;
  for (let off = 60; off + BLOCK_ALIGN <= 60 + dataBytes && n < total; off += BLOCK_ALIGN) {
    let pred = v.getInt16(off, true);
    let index = wav[off + 2];
    out[n++] = pred;
    for (let k = 1; k < SAMPLES_PER_BLOCK && n < total; k++) {
      const byte = wav[off + 4 + ((k - 1) >> 1)];
      const code = (k - 1) & 1 ? byte >> 4 : byte & 15;
      const step = STEPS[index];
      let delta = step >> 3;
      if (code & 4) delta += step;
      if (code & 2) delta += step >> 1;
      if (code & 1) delta += step >> 2;
      pred = clamp(code & 8 ? pred - delta : pred + delta, -32768, 32767);
      index = clamp(index + INDEX_ADJUST[code], 0, 88);
      out[n++] = pred;
    }
  }
  return out;
}

/** Тихую запись с телефона — к пику ≈ −1 дБ (не больше ×8, чтобы не раздувать шум); длинная тишина по краям — прочь. */
export function normalize(samples: Float32Array): Float32Array {
  const threshold = 0.02;
  let start = 0;
  let end = samples.length;
  while (start < end && Math.abs(samples[start]) < threshold) start++;
  while (end > start && Math.abs(samples[end - 1]) < threshold) end--;
  const pad = Math.round(CLIP_RATE * 0.15);
  const cut = samples.slice(Math.max(0, start - pad), Math.min(samples.length, end + pad));
  let peak = 0;
  for (const s of cut) peak = Math.max(peak, Math.abs(s));
  if (peak === 0) return cut;
  const gain = Math.min(8, 0.89 / peak);
  for (let i = 0; i < cut.length; i++) cut[i] *= gain;
  return cut;
}

/** Любой звук, который понимает браузер (запись MediaRecorder, mp3/wav/m4a с телефона) → моно 16 кГц → WAV для точек. */
export async function toClipWav(encoded: ArrayBuffer): Promise<{ wav: Uint8Array; durationMs: number }> {
  const Ctx = window.AudioContext ?? (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext;
  const ctx = new Ctx();
  try {
    const decoded = await ctx.decodeAudioData(encoded.slice(0));
    const offline = new OfflineAudioContext(1, Math.max(1, Math.ceil(decoded.duration * CLIP_RATE)), CLIP_RATE);
    const src = offline.createBufferSource();
    src.buffer = decoded;
    src.connect(offline.destination);
    src.start();
    const rendered = await offline.startRendering();
    const samples = normalize(rendered.getChannelData(0));
    return { wav: encodeImaAdpcmWav(samples), durationMs: Math.round((samples.length / CLIP_RATE) * 1000) };
  } finally {
    void ctx.close();
  }
}

export function toBase64(bytes: Uint8Array): string {
  let s = "";
  for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(s);
}
