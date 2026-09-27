import { Socket } from "node:net";
import {
  BacklightLevel,
  checkIntegrity,
  encodeBacklightPayload,
  encodeFrame,
  encodeSecondsPayload,
  Format,
  FrameReader,
  HEADER_SIZE,
  MsgType,
  NackCode,
  nackCodeName,
  parseHello,
  type Frame,
  type FrameFields,
  type HelloStatus,
} from "./protocol.js";

/**
 * Набор проверок совместимости дисплея (docs/firmware-plan.md, «conformance»): один и тот же прогон для любой реализации стороны
 * дисплея — mock (displays/mockDisplay.ts), прошивки, собранной для ПК, Wokwi/QEMU и настоящей платы. Шлёт кадры сам, в том числе
 * заведомо битые (обычный сервер такие не отправит), и сверяет ответы с контрактом docs/displays.md.
 *
 * Прогон меняет состояние дисплея: на экране остаётся тестовый узор, версия картинки растёт. После прогона на настоящей точке
 * отправьте QR заново.
 */

export interface ConformanceTarget {
  host: string;
  port: number;
  deviceId: string;
  key: Buffer;
  width: number;
  height: number;
}

export interface ConformanceOptions {
  /** Подключение и HELLO. */
  connectTimeoutMs: number;
  /** Ответ на кадр (RECEIVED, NACK, OK). */
  replyTimeoutMs: number;
  /** DISPLAYED после RECEIVED — полное обновление e-paper. */
  displayTimeoutMs: number;
  /** Таймауты самого дисплея (контракт: 2 с и 5 с) — сколько ждать, что он закроет молчащее соединение. */
  headerTimeoutMs: number;
  payloadTimeoutMs: number;
  /** Запас сверх таймаутов дисплея. */
  marginMs: number;
  /** Сколько ждать, пока дисплей после REBOOT снова ответит. */
  rebootTimeoutMs: number;
  /** Картинок подряд в C19. */
  imagesInRow: number;
  log: (line: string) => void;
}

export const DEFAULT_CONFORMANCE_OPTIONS: ConformanceOptions = {
  connectTimeoutMs: 3000,
  replyTimeoutMs: 3000,
  displayTimeoutMs: 15000,
  headerTimeoutMs: 2000,
  payloadTimeoutMs: 5000,
  marginMs: 1500,
  rebootTimeoutMs: 20000,
  imagesInRow: 20,
  log: () => {},
};

export interface CaseResult {
  id: string;
  name: string;
  ok: boolean;
  detail: string;
  ms: number;
}

// ── Сырое соединение: всё видно, ничего не исправляется ──

type Next = Frame | "closed" | "timeout";

class RawConn {
  private readonly reader = new FrameReader();
  private readonly frames: Frame[] = [];
  private closed = false;
  private waiter: ((v: Next) => void) | null = null;
  nonce!: Buffer;
  hello!: { status: HelloStatus; displayed: number; width: number; height: number; deviceId: string; signed: boolean };

  private constructor(private readonly socket: Socket) {
    socket.setNoDelay(true);
    socket.on("data", (chunk: Buffer) => {
      this.reader.push(chunk);
      try {
        for (let f = this.reader.next(); f; f = this.reader.next()) this.push(f);
      } catch {
        socket.destroy();
      }
    });
    socket.on("error", () => {});
    socket.on("close", () => {
      this.closed = true;
      const w = this.waiter;
      this.waiter = null;
      w?.("closed");
    });
  }

  static async open(t: ConformanceTarget, timeoutMs: number): Promise<RawConn> {
    const socket = new Socket();
    await new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => {
        socket.destroy();
        reject(new Error(`no TCP connection to ${t.host}:${t.port} within ${timeoutMs} ms`));
      }, timeoutMs);
      socket.once("connect", () => {
        clearTimeout(timer);
        resolve();
      });
      socket.once("error", (err) => {
        clearTimeout(timer);
        reject(new Error(`cannot connect to ${t.host}:${t.port}: ${err.message}`));
      });
      socket.connect({ host: t.host, port: t.port });
    });
    const conn = new RawConn(socket);
    const first = await conn.next(timeoutMs);
    if (first === "closed" || first === "timeout") {
      conn.destroy();
      throw new Error(`no HELLO (${first})`);
    }
    const hello = parseHello(first);
    if (!hello) {
      conn.destroy();
      throw new Error(`first frame is type 0x${first.header.type.toString(16)}, not HELLO`);
    }
    conn.nonce = hello.nonce;
    conn.hello = {
      status: hello.status,
      displayed: first.header.seq,
      width: first.header.width,
      height: first.header.height,
      deviceId: first.header.deviceId,
      signed: checkIntegrity(first, t.key, hello.nonce) === null,
    };
    return conn;
  }

  private push(f: Frame): void {
    const w = this.waiter;
    if (w) {
      this.waiter = null;
      w(f);
    } else this.frames.push(f);
  }

  next(timeoutMs: number): Promise<Next> {
    const queued = this.frames.shift();
    if (queued) return Promise.resolve(queued);
    if (this.closed) return Promise.resolve("closed");
    return new Promise<Next>((resolve) => {
      const timer = setTimeout(() => {
        this.waiter = null;
        resolve("timeout");
      }, timeoutMs);
      this.waiter = (v) => {
        clearTimeout(timer);
        resolve(v);
      };
    });
  }

  /** Закрыл ли дисплей соединение за timeoutMs (кадры, пришедшие до закрытия, пропускаются). */
  async waitClosed(timeoutMs: number): Promise<boolean> {
    const deadline = Date.now() + timeoutMs;
    for (;;) {
      const left = deadline - Date.now();
      if (left <= 0) return this.closed;
      const n = await this.next(left);
      if (n === "closed") return true;
      if (n === "timeout") return false;
    }
  }

  get isClosed(): boolean {
    return this.closed;
  }

  write(bytes: Buffer): void {
    if (!this.closed) this.socket.write(bytes);
  }

  destroy(): void {
    this.socket.destroy();
  }
}

// ── Кадры ──

/** Тестовый узор — шахматка 16 px: на e-paper сразу видно, что кадр пришёл целиком и не сдвинут. */
export function testPattern(width: number, height: number, phase = 0): Buffer {
  const stride = Math.ceil(width / 8);
  const data = Buffer.alloc(stride * height);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      if (((x >> 4) + (y >> 4) + phase) % 2 === 0) data[y * stride + (x >> 3)] |= 0x80 >> (x & 7);
    }
  }
  return data;
}

function describe(n: Next): string {
  if (n === "closed" || n === "timeout") return n;
  const t = MsgType[n.header.type] ?? `0x${n.header.type.toString(16)}`;
  return n.header.type === MsgType.NACK ? `NACK ${nackCodeName(n.payload[0])} (seq ${n.header.seq})` : `${t} seq ${n.header.seq}`;
}

class CaseFailure extends Error {}

function expect(cond: unknown, message: string): asserts cond {
  if (!cond) throw new CaseFailure(message);
}

export async function runConformance(target: ConformanceTarget, options: Partial<ConformanceOptions> = {}, only?: string[]): Promise<CaseResult[]> {
  const o = { ...DEFAULT_CONFORMANCE_OPTIONS, ...options };
  const t = target;
  const open = () => RawConn.open(t, o.connectTimeoutMs);
  const sign = (conn: RawConn, f: Omit<FrameFields, "deviceId"> & { deviceId?: string }, key = t.key, nonce = conn.nonce) =>
    encodeFrame({ deviceId: t.deviceId, ...f }, key, nonce);
  const image = (conn: RawConn, seq: number, over: Partial<FrameFields> = {}) =>
    sign(conn, { type: MsgType.IMAGE, seq, width: t.width, height: t.height, format: Format.BPP1, payload: testPattern(t.width, t.height, seq % 2), ...over });

  /** Показанная версия по свежему HELLO. */
  async function shown(): Promise<number> {
    const c = await open();
    c.destroy();
    return c.hello.displayed;
  }

  async function expectReply(conn: RawConn, type: MsgType, seq: number | null, timeoutMs = o.replyTimeoutMs): Promise<Frame> {
    const n = await conn.next(timeoutMs);
    const want = `${MsgType[type]}${seq === null ? "" : ` seq ${seq}`}`;
    expect(n !== "closed" && n !== "timeout" && n.header.type === type && (seq === null || n.header.seq === seq), `ждали ${want}, пришло ${describe(n)}`);
    expect(checkIntegrity(n, t.key, conn.nonce) === null, `${want}: подпись ответа не сходится`);
    return n;
  }

  async function expectNack(conn: RawConn, code: NackCode): Promise<Frame> {
    const n = await conn.next(o.replyTimeoutMs);
    expect(n !== "closed" && n !== "timeout" && n.header.type === MsgType.NACK && n.payload[0] === code, `ждали NACK ${nackCodeName(code)}, пришло ${describe(n)}`);
    return n;
  }

  /** Кадр отвергнут, картинка на экране не изменилась. */
  async function rejected(build: (c: RawConn, v: number) => Buffer, code: NackCode): Promise<string> {
    const c = await open();
    const before = c.hello.displayed;
    c.write(build(c, before));
    await expectNack(c, code);
    c.destroy();
    const after = await shown();
    expect(after === before, `показанная версия изменилась: ${before} → ${after}`);
    return `NACK ${nackCodeName(code)}, на экране по-прежнему ${before}`;
  }

  /** Поток сломан: NACK с кодом и закрытие соединения. */
  async function closesWith(bytes: (c: RawConn) => Buffer, code: NackCode): Promise<string> {
    const c = await open();
    c.write(bytes(c));
    await expectNack(c, code);
    expect(await c.waitClosed(o.marginMs), "после NACK соединение не закрыто");
    return `NACK ${nackCodeName(code)} и закрытие`;
  }

  async function showImage(conn: RawConn, seq: number): Promise<void> {
    conn.write(image(conn, seq));
    await expectReply(conn, MsgType.RECEIVED, seq);
    await expectReply(conn, MsgType.DISPLAYED, seq, o.displayTimeoutMs);
  }

  const cases: { id: string; name: string; run: () => Promise<string> }[] = [
    {
      id: "C1",
      name: "HELLO: подпись, id, размер панели",
      run: async () => {
        const c = await open();
        c.destroy();
        expect(c.hello.deviceId === t.deviceId, `id в HELLO "${c.hello.deviceId}", ждали "${t.deviceId}"`);
        expect(c.hello.signed, "подпись HELLO не сходится — секрет в плате не тот");
        expect(c.hello.width === t.width && c.hello.height === t.height, `панель ${c.hello.width}×${c.hello.height}, ждали ${t.width}×${t.height}`);
        return `показывает ${c.hello.displayed}, статус ${JSON.stringify(c.hello.status)}`;
      },
    },
    {
      id: "C2",
      name: "IMAGE: RECEIVED → DISPLAYED, версия сохраняется",
      run: async () => {
        const c = await open();
        const v = c.hello.displayed + 1;
        const started = Date.now();
        await showImage(c, v);
        const took = Date.now() - started;
        c.destroy();
        expect((await shown()) === v, "HELLO следующего соединения не показывает новую версию");
        return `версия ${v}, до DISPLAYED ${took} мс`;
      },
    },
    { id: "C3", name: "неверный MAGIC", run: () => closesWith((c) => Object.assign(image(c, c.hello.displayed + 1), { 0: 0x58 }), NackCode.BAD_MAGIC) },
    { id: "C4", name: "неверная версия протокола", run: () => closesWith((c) => Object.assign(image(c, c.hello.displayed + 1), { 5: 2 }), NackCode.BAD_VERSION) },
    {
      id: "C5",
      name: "длина payload больше буфера",
      run: () =>
        closesWith((c) => {
          const h = Buffer.from(image(c, c.hello.displayed + 1).subarray(0, HEADER_SIZE));
          h.writeUInt32BE(0xfffffff0, 52);
          return h;
        }, NackCode.BAD_LENGTH),
    },
    {
      id: "C6",
      name: "оборванный кадр: закрытие по таймауту payload",
      run: async () => {
        const c = await open();
        const before = c.hello.displayed;
        const bytes = image(c, before + 1);
        c.write(bytes.subarray(0, HEADER_SIZE + Math.floor((bytes.length - HEADER_SIZE) / 2)));
        const started = Date.now();
        const closed = await c.waitClosed(o.payloadTimeoutMs + o.marginMs);
        expect(closed, `соединение не закрыто за ${o.payloadTimeoutMs + o.marginMs} мс`);
        expect((await shown()) === before, "оборванный кадр показан");
        return `закрыто через ${Date.now() - started} мс`;
      },
    },
    {
      id: "C7",
      name: "испорченный payload — BAD_CRC",
      run: () =>
        rejected((c, v) => {
          const b = image(c, v + 1);
          b[HEADER_SIZE + 7] ^= 0x10;
          return b;
        }, NackCode.BAD_CRC),
    },
    { id: "C8", name: "чужой секрет — AUTH_FAILED", run: () => rejected((c, v) => sign(c, { type: MsgType.IMAGE, seq: v + 1, width: t.width, height: t.height, format: Format.BPP1, payload: testPattern(t.width, t.height) }, Buffer.alloc(32, 7)), NackCode.AUTH_FAILED) },
    {
      id: "C9",
      name: "кадр с nonce прошлого соединения — AUTH_FAILED",
      run: async () => {
        const first = await open();
        const oldNonce = first.nonce;
        first.destroy();
        await new Promise((r) => setTimeout(r, 50));
        return rejected((c, v) => sign(c, { type: MsgType.BACKLIGHT, payload: encodeBacklightPayload(BacklightLevel.OFF, 0), seq: v }, t.key, oldNonce), NackCode.AUTH_FAILED);
      },
    },
    { id: "C10", name: "версия ниже показанной — STALE_VERSION", run: () => rejected((c, v) => image(c, Math.max(0, v - 1)), NackCode.STALE_VERSION) },
    { id: "C11", name: "версия равна показанной — STALE_VERSION", run: () => rejected((c, v) => image(c, v), NackCode.STALE_VERSION) },
    { id: "C12", name: "кадр другому дисплею — WRONG_DEVICE", run: () => rejected((c, v) => sign(c, { deviceId: "display-other", type: MsgType.IMAGE, seq: v + 1, width: t.width, height: t.height, format: Format.BPP1, payload: testPattern(t.width, t.height) }), NackCode.WRONG_DEVICE) },
    {
      id: "C13",
      name: "не тот размер кадра (перепутана ориентация) — BAD_FORMAT",
      // Кадр того же размера в байтах, что панель: больший упёрся бы в приёмный буфер и законно получил бы BAD_LENGTH по заголовку.
      run: () =>
        rejected((c, v) => {
          const [w, h] = t.width !== t.height ? [t.height, t.width] : [t.width - 8, t.height];
          return image(c, v + 1, { width: w, height: h, payload: testPattern(w, h) });
        }, NackCode.BAD_FORMAT),
    },
    {
      id: "C14",
      name: "TEST, BACKLIGHT, REBOOT — OK; после перезагрузки та же версия",
      run: async () => {
        const c = await open();
        const before = c.hello.displayed;
        c.write(sign(c, { type: MsgType.TEST, payload: encodeSecondsPayload(2) }));
        await expectReply(c, MsgType.OK, null);
        c.write(sign(c, { type: MsgType.BACKLIGHT, payload: encodeBacklightPayload(BacklightLevel.MEDIUM, 3) }));
        await expectReply(c, MsgType.OK, null);
        c.write(sign(c, { type: MsgType.BACKLIGHT, payload: encodeBacklightPayload(BacklightLevel.OFF, 0) }));
        await expectReply(c, MsgType.OK, null);
        c.write(sign(c, { type: MsgType.REBOOT }));
        await expectReply(c, MsgType.OK, null);
        expect(await c.waitClosed(o.marginMs + 2000), "после REBOOT соединение не закрыто");
        const started = Date.now();
        for (;;) {
          try {
            const after = await shown();
            expect(after === before, `после перезагрузки показывает ${after}, было ${before}`);
            return `снова на связи через ${Date.now() - started} мс, версия ${after}`;
          } catch (err) {
            if (err instanceof CaseFailure) throw err;
            expect(Date.now() - started < o.rebootTimeoutMs, `не ответил за ${o.rebootTimeoutMs} мс после REBOOT`);
            await new Promise((r) => setTimeout(r, 500));
          }
        }
      },
    },
    { id: "C15", name: "подсветка уровня 9 — BAD_LENGTH", run: () => rejected((c) => sign(c, { type: MsgType.BACKLIGHT, payload: Buffer.from([9, 0, 5]) }), NackCode.BAD_LENGTH) },
    { id: "C16", name: "неизвестный тип — UNSUPPORTED_TYPE", run: () => rejected((c) => sign(c, { type: 0x7f as MsgType }), NackCode.UNSUPPORTED_TYPE) },
    {
      id: "C17",
      name: "второе соединение вытесняет первое",
      run: async () => {
        const a = await open();
        const b = await open();
        const aClosed = await a.waitClosed(o.marginMs);
        b.write(sign(b, { type: MsgType.BACKLIGHT, payload: encodeBacklightPayload(BacklightLevel.OFF, 0) }));
        await expectReply(b, MsgType.OK, null);
        b.destroy();
        a.destroy();
        expect(aClosed, "первое соединение осталось открытым");
        return "первое закрыто, второе обслужено";
      },
    },
    {
      id: "C18",
      name: "молчащее соединение закрывается по таймауту заголовка",
      run: async () => {
        const c = await open();
        const started = Date.now();
        expect(await c.waitClosed(o.headerTimeoutMs + o.marginMs), `не закрыто за ${o.headerTimeoutMs + o.marginMs} мс`);
        return `закрыто через ${Date.now() - started} мс`;
      },
    },
    {
      id: "C19",
      name: `${o.imagesInRow} картинок подряд`,
      run: async () => {
        const started = Date.now();
        let v = await shown();
        for (let i = 0; i < o.imagesInRow; i++) {
          const c = await open();
          v = c.hello.displayed + 1;
          await showImage(c, v);
          c.destroy();
        }
        expect((await shown()) === v, "последняя версия не сохранилась");
        return `в среднем ${Math.round((Date.now() - started) / o.imagesInRow)} мс на картинку`;
      },
    },
    {
      id: "C20",
      name: "IMAGE во время обновления панели",
      run: async () => {
        const c = await open();
        const v1 = c.hello.displayed + 1;
        const v2 = v1 + 1;
        c.write(image(c, v1));
        await expectReply(c, MsgType.RECEIVED, v1);
        c.write(image(c, v2));
        // Допустимы два поведения: второй кадр отвергнут BUSY (первый показан) или поставлен в очередь и показан после первого.
        let busy = false;
        let v2Received = false;
        let v1Shown = false;
        let v2Shown = false;
        const seen: string[] = [];
        const deadline = Date.now() + 2 * o.displayTimeoutMs;
        while (!(v1Shown && (busy || v2Shown))) {
          const n = await c.next(Math.max(1, deadline - Date.now()));
          seen.push(describe(n));
          expect(n !== "closed" && n !== "timeout", `ждали ответов на ${v1} и ${v2}, пришло: ${seen.join(", ")}`);
          if (n.header.type === MsgType.NACK && n.payload[0] === NackCode.BUSY && !v2Received) busy = true;
          else if (n.header.type === MsgType.RECEIVED && n.header.seq === v2 && !busy) v2Received = true;
          else if (n.header.type === MsgType.DISPLAYED && n.header.seq === v1) v1Shown = true;
          else if (n.header.type === MsgType.DISPLAYED && n.header.seq === v2 && v2Received) v2Shown = true;
          else expect(false, `неожиданный ответ: ${seen.join(", ")}`);
        }
        const v2Accepted = v2Received;
        c.destroy();
        const final = await shown();
        const want = v2Accepted ? v2 : v1;
        expect(final === want, `на экране ${final}, ждали ${want} — старый кадр поверх нового?`);
        return v2Accepted ? "второй кадр поставлен в очередь и показан после первого" : "второй кадр отвергнут BUSY, первый показан";
      },
    },
  ];

  const results: CaseResult[] = [];
  for (const c of cases) {
    if (only && !only.includes(c.id)) continue;
    const started = Date.now();
    let result: CaseResult;
    try {
      result = { id: c.id, name: c.name, ok: true, detail: await c.run(), ms: 0 };
    } catch (err) {
      result = { id: c.id, name: c.name, ok: false, detail: err instanceof Error ? err.message : String(err), ms: 0 };
    }
    result.ms = Date.now() - started;
    o.log(`${result.ok ? "ok  " : "FAIL"} ${result.id} ${result.name}: ${result.detail}`);
    results.push(result);
    // Без HELLO дальше проверять нечего.
    if (c.id === "C1" && !result.ok) break;
  }
  return results;
}
