import { randomBytes } from "node:crypto";
import { createServer, type Server, type Socket } from "node:net";
import type { AddressInfo } from "node:net";
import {
  encodeFrame,
  encodeHello,
  encodeNackPayload,
  Format,
  FrameReader,
  MsgType,
  NackCode,
  nackCodeName,
  ProtocolError,
  validateIncoming,
  type HelloStatus,
} from "./protocol.js";

/**
 * Дисплей без железа: та же сторона протокола, что у прошивки ESP32 (docs/displays.md), — TCP-сервер, HELLO с nonce,
 * проверки в эталонном порядке (protocol.ts, validateIncoming), RECEIVED → «обновление e-paper» → DISPLAYED.
 * Нужен для тестов менеджера и для прогона дашборда на ПК: `npm run mock-display` (scripts/mockDisplay.ts) пишет каждый
 * показанный кадр в PNG. Неисправности (обрыв, молчание, битый CRC, отказ панели) включаются полями faults.
 */

export interface MockFaults {
  /** Закрыть столько следующих соединений сразу после accept (дисплей перезагружается / пропал Wi-Fi). */
  dropConnections?: number;
  /** Не слать HELLO столько раз (зависшая прошивка — сработает таймаут HELLO). */
  silentHello?: number;
  /** Не слать DISPLAYED столько раз (панель зависла или ответ потерялся), но картинку показать. */
  loseDisplayed?: number;
  /** Ответить NACK DISPLAY_FAILED столько раз вместо обновления панели. */
  failDisplay?: number;
  /** Испортить CRC в следующих N кадрах, пришедших к дисплею (как будто байты побились по дороге). */
  corruptIncoming?: number;
}

export interface MockDisplayOptions {
  deviceId: string;
  key: Buffer;
  width: number;
  height: number;
  host?: string;
  /** 0 — любой свободный. */
  port?: number;
  displayedVersion?: number;
  /** Сколько «обновляется e-paper» между RECEIVED и DISPLAYED. */
  displayDelayMs?: number;
  status?: HelloStatus;
  faults?: MockFaults;
  /** Кадр показан: сюда — сохранить во «flash» (CLI пишет PNG и версию). */
  onDisplayed?: (version: number, framebuffer: Buffer) => void;
  log?: (line: string) => void;
}

export interface MockEvent {
  type: string;
  seq: number;
  at: number;
}

export class MockDisplay {
  readonly faults: MockFaults;
  displayedVersion: number;
  framebuffer: Buffer | null = null;
  backlight = 0;
  connections = 0;
  /** Сколько соединений открыто прямо сейчас и максимум за всё время — проверка «не больше одного на дисплей». */
  openConnections = 0;
  maxOpenConnections = 0;
  readonly received: MockEvent[] = [];
  private server: Server | null = null;
  private readonly sockets = new Set<Socket>();

  constructor(readonly options: MockDisplayOptions) {
    this.displayedVersion = options.displayedVersion ?? 0;
    this.faults = { ...options.faults };
  }

  get port(): number {
    return (this.server!.address() as AddressInfo).port;
  }

  async start(): Promise<number> {
    this.server = createServer((socket) => this.accept(socket));
    await new Promise<void>((resolve, reject) => {
      this.server!.once("error", reject);
      this.server!.listen(this.options.port ?? 0, this.options.host ?? "127.0.0.1", () => resolve());
    });
    return this.port;
  }

  async stop(): Promise<void> {
    for (const s of this.sockets) s.destroy();
    await new Promise<void>((resolve) => (this.server ? this.server.close(() => resolve()) : resolve()));
    this.server = null;
  }

  private log(line: string): void {
    this.options.log?.(`[MOCK ${this.options.deviceId}] ${line}`);
  }

  private take(fault: keyof MockFaults): boolean {
    const n = this.faults[fault] ?? 0;
    if (n <= 0) return false;
    this.faults[fault] = n - 1;
    return true;
  }

  private accept(socket: Socket): void {
    this.connections++;
    this.sockets.add(socket);
    this.openConnections++;
    this.maxOpenConnections = Math.max(this.maxOpenConnections, this.openConnections);
    socket.on("close", () => {
      this.sockets.delete(socket);
      this.openConnections--;
    });
    socket.on("error", () => {});
    if (this.take("dropConnections")) {
      this.log("drop connection");
      socket.destroy();
      return;
    }
    const { deviceId, key, width, height } = this.options;
    const nonce = randomBytes(16);
    const reply = (type: MsgType, seq: number, payload?: Buffer) => {
      if (!socket.destroyed) socket.write(encodeFrame({ type, deviceId, seq, width, height, format: Format.BPP1, payload }, key, nonce));
    };
    const nack = (code: NackCode, message = "") => {
      this.log(`NACK ${nackCodeName(code)} ${message}`);
      reply(MsgType.NACK, this.displayedVersion, encodeNackPayload(code, message));
    };

    if (!this.take("silentHello")) {
      socket.write(encodeHello(deviceId, key, nonce, this.displayedVersion, width, height, { fw: "mock-1.0", hw: "mock", ...this.options.status }));
    }

    const reader = new FrameReader();
    let busy = false;
    socket.on("data", (chunk: Buffer) => {
      reader.push(chunk);
      for (;;) {
        let frame;
        try {
          frame = reader.next();
        } catch (err) {
          // Граница кадра потеряна — дальше поток не разобрать: NACK и закрыть, как прошивка.
          nack(err instanceof ProtocolError ? err.code : NackCode.BAD_LENGTH, String(err));
          socket.end();
          return;
        }
        if (!frame) return;
        if (this.take("corruptIncoming") && frame.payload.length > 0) frame.payload[0] ^= 0xff;
        this.received.push({ type: MsgType[frame.header.type] ?? String(frame.header.type), seq: frame.header.seq, at: Date.now() });
        const code = validateIncoming(frame, key, nonce, { deviceId, width, height, displayedVersion: this.displayedVersion });
        if (code !== null) {
          nack(code);
          continue;
        }
        if (busy) {
          nack(NackCode.BUSY);
          continue;
        }
        switch (frame.header.type) {
          case MsgType.IMAGE: {
            const seq = frame.header.seq;
            reply(MsgType.RECEIVED, seq);
            busy = true;
            setTimeout(() => {
              busy = false;
              if (this.take("failDisplay")) {
                nack(NackCode.DISPLAY_FAILED, "panel update failed");
                return;
              }
              // Сначала «flash», потом панель, потом ответ — перезапуск посреди обновления восстановит уже новый кадр.
              this.framebuffer = frame.payload;
              this.displayedVersion = seq;
              this.options.onDisplayed?.(seq, frame.payload);
              this.log(`displayed image=${seq}`);
              if (!this.take("loseDisplayed")) reply(MsgType.DISPLAYED, seq);
            }, this.options.displayDelayMs ?? 0);
            break;
          }
          case MsgType.TEST:
            this.log(`test screen for ${frame.payload.readUInt16BE(0)} s`);
            reply(MsgType.OK, this.displayedVersion);
            break;
          case MsgType.BACKLIGHT:
            this.backlight = frame.payload[0];
            this.log(`backlight=${this.backlight} for ${frame.payload.readUInt16BE(1)} s`);
            reply(MsgType.OK, this.displayedVersion);
            break;
          case MsgType.REBOOT:
            reply(MsgType.OK, this.displayedVersion);
            this.log("reboot");
            socket.end();
            break;
        }
      }
    });
  }
}
