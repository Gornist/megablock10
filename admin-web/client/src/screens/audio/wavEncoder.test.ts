import { describe, expect, it } from "vitest";
import { CLIP_RATE, SAMPLES_PER_BLOCK, decodeImaAdpcm, encodeImaAdpcmWav, normalize, toBase64 } from "./wavEncoder";

describe("wavEncoder", () => {
  it("заголовок: IMA ADPCM, моно, 16 кГц, блок 256 байт, число сэмплов в fact", () => {
    const wav = encodeImaAdpcmWav(new Float32Array(1000));
    const v = new DataView(wav.buffer);
    expect(String.fromCharCode(...wav.subarray(0, 4))).toBe("RIFF");
    expect(v.getUint16(20, true)).toBe(0x11);
    expect(v.getUint16(22, true)).toBe(1);
    expect(v.getUint32(24, true)).toBe(CLIP_RATE);
    expect(v.getUint16(32, true)).toBe(256);
    expect(v.getUint16(38, true)).toBe(SAMPLES_PER_BLOCK);
    expect(v.getUint32(48, true)).toBe(1000);
    expect(v.getUint32(56, true)).toBe(2 * 256); // 1000 сэмплов — два блока по 505
    expect(wav.length).toBe(60 + 512);
  });

  it("синус 440 Гц переживает кодирование: ошибка после декодирования мала", () => {
    const n = CLIP_RATE; // секунда
    const src = new Float32Array(n);
    for (let i = 0; i < n; i++) src[i] = 0.5 * Math.sin((2 * Math.PI * 440 * i) / CLIP_RATE);
    const back = decodeImaAdpcm(encodeImaAdpcmWav(src));
    expect(back.length).toBe(n);
    let err = 0;
    for (let i = 0; i < n; i++) err += (back[i] / 32767 - src[i]) ** 2;
    const rms = Math.sqrt(err / n);
    expect(rms).toBeLessThan(0.02);
  });

  it("нормализация: тихая запись — громче, тишина по краям обрезается", () => {
    const s = new Float32Array(CLIP_RATE * 2);
    for (let i = CLIP_RATE / 2; i < CLIP_RATE; i++) s[i] = 0.2 * Math.sin(i / 5);
    const out = normalize(s);
    expect(out.length).toBeLessThan(CLIP_RATE);
    expect(Math.max(...out.map(Math.abs))).toBeCloseTo(0.89, 2);
  });

  it("base64 длинного клипа без переполнения стека", () => {
    const b = new Uint8Array(300_000).fill(65);
    expect(toBase64(b).length).toBe(400_000);
  });
});
