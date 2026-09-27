import { Socket } from "node:net";
import {
  checkIntegrity,
  encodeFrame,
  FrameReader,
  MsgType,
  NackCode,
  nackCodeName,
  parseHello,
  ProtocolError,
  type Frame,
  type FrameFields,
  type HelloStatus,
} from "./protocol.js";

/**
 * Одно TCP-соединение сервера с дисплеем: connect → HELLO дисплея (nonce, статус) → запросы/ответы → close.
 * Всё, что пришло от дисплея, проверяется здесь же (CRC, HMAC на nonce соединения, id устройства) — выше уходят только
 * подлинные кадры. Любая неудача — DisplayFailure: retryable говорит менеджеру, есть ли смысл повторять.
 */

export type FailureKind = "CONNECT" | "TIMEOUT" | "DISCONNECT" | "PROTOCOL" | "AUTH" | "CRC" | "NACK" | "CONFIG";

export class DisplayFailure extends Error {
  constructor(
    readonly kind: FailureKind,
    message: string,
    readonly retryable: boolean,
    readonly nack?: NackCode,
    /** Версия, которую дисплей показывает по его ответу (NACK/HELLO). */
    readonly displayedVersion?: number,
  ) {
    super(message);
  }

  /** Коротко для журнала и UI: «TIMEOUT: нет DISPLAYED за 10000 мс». */
  get summary(): string {
    return `${this.nack !== undefined ? nackCodeName(this.nack) : this.kind}: ${this.message}`;
  }
}

export interface SessionTarget {
  host: string;
  port: number;
  deviceId: string;
  key: Buffer;
}

export interface HelloInfo {
  nonce: Buffer;
  status: HelloStatus;
  displayedVersion: number;
  width: number;
  height: number;
}

export class DisplaySession {
  private readonly reader = new FrameReader();
  private readonly frames: Frame[] = [];
  private waiter: { resolve: (f: Frame) => void; reject: (e: DisplayFailure) => void } | null = null;
  private failure: DisplayFailure | null = null;
  private nonce: Buffer | null = null;
  hello!: HelloInfo;

  private constructor(
    private readonly socket: Socket,
    private readonly target: SessionTarget,
  ) {
    socket.setNoDelay(true);
    socket.on("data", (chunk: Buffer) => this.onData(chunk));
    socket.on("error", (err) => this.fail(new DisplayFailure("DISCONNECT", `socket error: ${err.message}`, true)));
    socket.on("close", () => this.fail(new DisplayFailure("DISCONNECT", "connection closed by display", true)));
  }

  /** Подключиться и дождаться подлинного HELLO. Ошибка — DisplayFailure, сокет к этому моменту уже закрыт. */
  static async open(target: SessionTarget, timeouts: { connectMs: number; helloMs: number }, track?: (s: Socket) => () => void): Promise<DisplaySession> {
    const socket = new Socket();
    const untrack = track?.(socket);
    socket.once("close", () => untrack?.());
    await new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => {
        socket.destroy();
        reject(new DisplayFailure("CONNECT", `no TCP connection to ${target.host}:${target.port} within ${timeouts.connectMs} ms`, true));
      }, timeouts.connectMs);
      socket.once("connect", () => {
        clearTimeout(timer);
        resolve();
      });
      socket.once("error", (err) => {
        clearTimeout(timer);
        socket.destroy();
        reject(new DisplayFailure("CONNECT", `cannot connect to ${target.host}:${target.port}: ${err.message}`, true));
      });
      socket.connect({ host: target.host, port: target.port });
    });
    const session = new DisplaySession(socket, target);
    try {
      await session.readHello(timeouts.helloMs);
    } catch (err) {
      await session.close();
      throw err;
    }
    return session;
  }

  private async readHello(timeoutMs: number): Promise<void> {
    const frame = await this.nextRaw(timeoutMs, "HELLO");
    const hello = parseHello(frame);
    if (!hello) throw new DisplayFailure("PROTOCOL", `expected HELLO, got type 0x${frame.header.type.toString(16)}`, true);
    if (frame.header.deviceId !== this.target.deviceId) {
      throw new DisplayFailure("CONFIG", `${this.target.host}:${this.target.port} answers as "${frame.header.deviceId}", not "${this.target.deviceId}"`, false, NackCode.WRONG_DEVICE);
    }
    const integrity = checkIntegrity(frame, this.target.key, hello.nonce);
    if (integrity === NackCode.BAD_CRC) throw new DisplayFailure("CRC", "HELLO failed CRC", true, NackCode.BAD_CRC);
    if (integrity === NackCode.AUTH_FAILED) {
      throw new DisplayFailure("AUTH", "HELLO signature does not match the display secret", false, NackCode.AUTH_FAILED);
    }
    this.nonce = hello.nonce;
    this.hello = { nonce: hello.nonce, status: hello.status, displayedVersion: frame.header.seq, width: frame.header.width, height: frame.header.height };
  }

  send(fields: Omit<FrameFields, "deviceId">): void {
    if (!this.nonce) throw new Error("session is not open");
    if (this.failure) throw this.failure;
    this.socket.write(encodeFrame({ ...fields, deviceId: this.target.deviceId }, this.target.key, this.nonce));
  }

  /** Следующий подлинный кадр от дисплея; stage — чего ждём, для текста таймаута. */
  async next(timeoutMs: number, stage: string): Promise<Frame> {
    const frame = await this.nextRaw(timeoutMs, stage);
    if (frame.header.deviceId !== this.target.deviceId) {
      throw new DisplayFailure("PROTOCOL", `frame from "${frame.header.deviceId}" in session with "${this.target.deviceId}"`, false, NackCode.WRONG_DEVICE);
    }
    const integrity = checkIntegrity(frame, this.target.key, this.nonce!);
    if (integrity === NackCode.BAD_CRC) throw new DisplayFailure("CRC", `${stage}: reply failed CRC`, true, NackCode.BAD_CRC);
    if (integrity === NackCode.AUTH_FAILED) throw new DisplayFailure("AUTH", `${stage}: reply signature mismatch`, false, NackCode.AUTH_FAILED);
    return frame;
  }

  private nextRaw(timeoutMs: number, stage: string): Promise<Frame> {
    const queued = this.frames.shift();
    if (queued) return Promise.resolve(queued);
    if (this.failure) return Promise.reject(this.failure);
    return new Promise<Frame>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.waiter = null;
        reject(new DisplayFailure("TIMEOUT", `no ${stage} within ${timeoutMs} ms`, true));
      }, timeoutMs);
      this.waiter = {
        resolve: (f) => {
          clearTimeout(timer);
          resolve(f);
        },
        reject: (e) => {
          clearTimeout(timer);
          reject(e);
        },
      };
    });
  }

  private onData(chunk: Buffer): void {
    this.reader.push(chunk);
    try {
      for (let f = this.reader.next(); f; f = this.reader.next()) this.deliver(f);
    } catch (err) {
      const message = err instanceof ProtocolError ? err.message : String(err);
      this.fail(new DisplayFailure("PROTOCOL", `malformed data from display: ${message}`, true, err instanceof ProtocolError ? err.code : undefined));
      this.socket.destroy();
    }
  }

  private deliver(frame: Frame): void {
    if (this.waiter) {
      const w = this.waiter;
      this.waiter = null;
      w.resolve(frame);
    } else {
      this.frames.push(frame);
    }
  }

  private fail(failure: DisplayFailure): void {
    if (this.failure) return;
    this.failure = failure;
    if (this.waiter) {
      const w = this.waiter;
      this.waiter = null;
      w.reject(failure);
    }
  }

  /**
   * Закрыть и дождаться, пока соединение закроется с обеих сторон: следующее соединение к этому дисплею откроется только после,
   * так что прошивке хватает одного клиента за раз. Дисплей не закрывает свою сторону — через секунду сокет рвётся.
   */
  close(): Promise<void> {
    if (this.socket.destroyed) return Promise.resolve();
    return new Promise<void>((resolve) => {
      const timer = setTimeout(() => this.socket.destroy(), 1000);
      this.socket.once("close", () => {
        clearTimeout(timer);
        resolve();
      });
      this.socket.end();
    });
  }
}

/** Ответ дисплея на запрос: NACK превращается в DisplayFailure, прочее — ожидаемый тип или ошибка протокола. */
export function expectReply(frame: Frame, expected: MsgType, stage: string): Frame {
  if (frame.header.type === MsgType.NACK) {
    const code = frame.payload[0] as NackCode;
    const text = frame.payload.subarray(1).toString("utf8");
    throw new DisplayFailure("NACK", `${stage}: display refused${text ? ` (${text})` : ""}`, NACK_RETRYABLE.has(code), code, frame.header.seq);
  }
  if (frame.header.type !== expected) {
    throw new DisplayFailure("PROTOCOL", `${stage}: expected type 0x${expected.toString(16)}, got 0x${frame.header.type.toString(16)}`, true);
  }
  return frame;
}

/**
 * Какие отказы стоит повторить: порча при передаче, занятость и сбой обновления панели — да; неверный секрет, чужой id, не тот
 * размер кадра, неизвестная версия протокола — повтор даст то же самое. STALE_VERSION менеджер разбирает сам (перенумерация).
 */
const NACK_RETRYABLE = new Set<NackCode>([NackCode.BAD_CRC, NackCode.BAD_LENGTH, NackCode.BUSY, NackCode.DISPLAY_FAILED]);
