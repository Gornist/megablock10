import { createHash, randomBytes } from "node:crypto";
import { parseWav } from "../audio/wav.js";
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
  LIST_REPLY_MAX,
  type AnnouncePayload,
  type AudioHelloStatus,
  type AudioStatePayload,
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
  /** Звук: оборвать соединение после первого принятого куска клипа столько раз (Wi-Fi пропал посреди загрузки — докачка). */
  dropMidClip?: number;
  /** Звук: ответить OK на AUDIO_STATE с задержкой (состояние уже принято, сервер ещё ждёт ответа). */
  audioStateReplyDelayMs?: number;
}

export interface MockDisplayOptions {
  deviceId: string;
  key: Buffer;
  /** Что умеет точка (HELLO roles): по умолчанию только дисплей. С "audio" — звуковая точка (docs/sound-nodes.md). */
  roles?: ("display" | "audio")[];
  /** Треки на «карте» звуковой точки. */
  tracks?: string[];
  /** Во сколько раз быстрее «играть» объявления (тесты): длительность клипа × announceSpeed. */
  announceSpeed?: number;
  width: number;
  height: number;
  host?: string;
  /** 0 — любой свободный. */
  port?: number;
  displayedVersion?: number;
  /** Сколько «обновляется e-paper» между RECEIVED и DISPLAYED. */
  displayDelayMs?: number;
  /** Соединение без данных закрывается через столько (docs/displays.md: таймаут заголовка 2 с). */
  headerTimeoutMs?: number;
  /** Начатый кадр должен дойти целиком за столько, иначе соединение закрывается (таймаут payload 5 с). */
  payloadTimeoutMs?: number;
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
  // ── Звук ──
  audioVersion = 0;
  audioState: AudioStatePayload | null = null;
  /** Принятые клипы по sha256 (hex) и недокачанные — переживают обрыв соединения, как файл .part на карте. */
  readonly clips = new Map<string, Buffer>();
  private readonly partialClips = new Map<string, { length: number; data: Buffer[]; have: number }>();
  announcement: { id: number; clip: string; state: "playing" | "done" | "failed" | "stopped"; timer?: NodeJS.Timeout } | null = null;
  private server: Server | null = null;
  private readonly sockets = new Set<Socket>();
  /** Обслуживаемое соединение: новое вытесняет его (полуоткрытое после обрыва Wi-Fi не должно занимать дисплей навсегда). */
  private active: Socket | null = null;

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

  get isAudio(): boolean {
    return this.options.roles?.includes("audio") ?? false;
  }

  /** Что звуковая точка докладывает в HELLO. */
  audioStatus(): AudioHelloStatus {
    const card = new Set(this.options.tracks ?? []);
    const wanted = this.audioState?.tracks ?? [];
    const present = wanted.filter((t) => card.has(t));
    return {
      v: this.audioVersion,
      playing: this.announcement?.state === "playing" ? null : (present[0] ?? null),
      vol: this.audioState?.volume ?? 0,
      tracks: card.size,
      sd: true,
      missing: wanted.filter((t) => !card.has(t)),
      ...(this.announcement ? { ann: { id: this.announcement.id, state: this.announcement.state } } : {}),
    };
  }

  async stop(): Promise<void> {
    if (this.announcement?.timer) clearTimeout(this.announcement.timer);
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
    if (this.active && !this.active.destroyed) {
      this.log("new connection replaces the previous one");
      this.active.destroy();
    }
    this.active = socket;
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
      const roles = this.options.roles ? { roles: this.options.roles, ...(this.isAudio ? { audio: this.audioStatus() } : {}) } : {};
      socket.write(encodeHello(deviceId, key, nonce, this.displayedVersion, width, height, { fw: "mock-1.0", hw: "mock", ...roles, ...this.options.status }));
    }

    const reader = new FrameReader();
    // Клип, начатый CLIP_BEGIN в этом соединении.
    const session: { clip: string | null } = { clip: null };
    let busy = false;
    // Таймауты как у прошивки: без данных — заголовок, начатый кадр — payload; пока панель обновляется, не отсчитываются.
    let timer: NodeJS.Timeout | null = null;
    let frameStartedAt: number | null = null;
    const headerMs = this.options.headerTimeoutMs ?? 2000;
    const payloadMs = this.options.payloadTimeoutMs ?? 5000;
    const arm = () => {
      if (timer) clearTimeout(timer);
      timer = null;
      if (busy || socket.destroyed) return;
      if (reader.pendingBytes === 0) {
        frameStartedAt = null;
        timer = setTimeout(() => {
          this.log("header timeout — closing");
          socket.destroy();
        }, headerMs);
      } else {
        frameStartedAt ??= Date.now();
        timer = setTimeout(
          () => {
            this.log("payload timeout — closing");
            socket.destroy();
          },
          Math.max(0, payloadMs - (Date.now() - frameStartedAt)),
        );
      }
    };
    socket.on("close", () => timer && clearTimeout(timer));
    arm();
    socket.on("data", (chunk: Buffer) => {
      reader.push(chunk);
      this.handle(socket, reader, () => busy, (b) => (busy = b), nonce, reply, nack, arm, session);
      arm();
    });
  }

  private handle(
    socket: Socket,
    reader: FrameReader,
    isBusy: () => boolean,
    setBusy: (b: boolean) => void,
    nonce: Buffer,
    reply: (type: MsgType, seq: number, payload?: Buffer) => void,
    nack: (code: NackCode, message?: string) => void,
    arm: () => void,
    session: { clip: string | null },
  ): void {
    const { deviceId, key, width, height } = this.options;
    {
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
        const code = validateIncoming(frame, key, nonce, { deviceId, width, height, displayedVersion: this.displayedVersion, audio: this.isAudio });
        if (code !== null) {
          nack(code);
          continue;
        }
        if (isBusy()) {
          nack(NackCode.BUSY);
          continue;
        }
        switch (frame.header.type) {
          case MsgType.IMAGE: {
            const seq = frame.header.seq;
            reply(MsgType.RECEIVED, seq);
            setBusy(true);
            setTimeout(() => {
              setBusy(false);
              arm();
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
          default:
            if (!this.handleAudio(frame.header.type, frame.header.seq, frame.payload, reply, nack, socket, session)) return;
        }
      }
    }
  }

  /** Звуковые команды (docs/sound-nodes.md). false — соединение закрыто (сбой dropMidClip). */
  private handleAudio(
    type: number,
    seq: number,
    payload: Buffer,
    reply: (type: MsgType, seq: number, payload?: Buffer) => void,
    nack: (code: NackCode, message?: string) => void,
    socket: Socket,
    session: { clip: string | null },
  ): boolean {
    const u32 = (n: number) => {
      const b = Buffer.alloc(4);
      b.writeUInt32BE(n, 0);
      return b;
    };
    switch (type) {
      case MsgType.AUDIO_STATE: {
        if (seq < this.audioVersion) {
          nack(NackCode.STALE_VERSION, `audio v${this.audioVersion}`);
          return true;
        }
        this.audioState = JSON.parse(payload.toString("utf8")) as AudioStatePayload;
        this.audioVersion = seq;
        this.log(`audio v${seq}: ${this.audioState.tracks.join(", ") || "тишина"} vol=${this.audioState.volume}`);
        const delay = this.faults.audioStateReplyDelayMs ?? 0;
        if (delay > 0) setTimeout(() => reply(MsgType.OK, seq), delay);
        else reply(MsgType.OK, seq);
        return true;
      }
      case MsgType.CLIP_BEGIN: {
        const sha = payload.subarray(0, 32).toString("hex");
        const length = payload.readUInt32BE(32);
        session.clip = sha;
        let have = length;
        if (!this.clips.has(sha)) {
          const part = this.partialClips.get(sha);
          if (!part || part.length !== length) this.partialClips.set(sha, { length, data: [], have: 0 });
          have = this.partialClips.get(sha)!.have;
        }
        reply(MsgType.OK, seq, u32(have));
        return true;
      }
      case MsgType.CLIP_CHUNK: {
        const part = session.clip ? this.partialClips.get(session.clip) : undefined;
        const offset = payload.readUInt32BE(0);
        if (!part || offset !== part.have) {
          nack(NackCode.BAD_LENGTH, `chunk at ${offset}, have ${part?.have ?? "no clip"}`);
          return true;
        }
        const data = payload.subarray(4);
        part.data.push(Buffer.from(data));
        part.have += data.length;
        if (this.take("dropMidClip")) {
          this.log("drop mid clip");
          socket.destroy();
          return false;
        }
        reply(MsgType.OK, seq, u32(part.have));
        return true;
      }
      case MsgType.CLIP_COMMIT: {
        const sha = session.clip;
        const part = sha ? this.partialClips.get(sha) : undefined;
        if (!sha || !part) {
          nack(NackCode.BAD_LENGTH, "no clip in progress");
          return true;
        }
        const data = Buffer.concat(part.data);
        this.partialClips.delete(sha);
        if (data.length !== part.length || createHash("sha256").update(data).digest("hex") !== sha) {
          nack(NackCode.BAD_CRC, "sha256 mismatch");
          return true;
        }
        this.clips.set(sha, data);
        reply(MsgType.OK, seq);
        return true;
      }
      case MsgType.ANNOUNCE: {
        const a = JSON.parse(payload.toString("utf8")) as AnnouncePayload;
        const clip = this.clips.get(a.clip);
        if (!clip) {
          nack(NackCode.MISSING_CLIP, a.clip);
          return true;
        }
        if (this.announcement?.timer) clearTimeout(this.announcement.timer);
        const durationMs = parseWav(clip)?.durationMs ?? 1000;
        const ann: NonNullable<MockDisplay["announcement"]> = { id: seq, clip: a.clip, state: "playing" };
        ann.timer = setTimeout(() => {
          if (ann.state === "playing") ann.state = "done";
          this.log(`announce ${seq} done`);
        }, durationMs * (this.options.announceSpeed ?? 1));
        ann.timer.unref();
        this.announcement = ann;
        this.log(`announce ${seq}: clip ${a.clip.slice(0, 8)} ${durationMs} ms, duck to ${a.duck}%`);
        reply(MsgType.OK, seq, Buffer.from(JSON.stringify({ durationMs })));
        return true;
      }
      case MsgType.ANNOUNCE_STOP:
        if (this.announcement?.state === "playing") {
          this.announcement.state = "stopped";
          if (this.announcement.timer) clearTimeout(this.announcement.timer);
        }
        reply(MsgType.OK, seq);
        return true;
      case MsgType.LIST: {
        const all = this.options.tracks ?? [];
        const start = payload.readUInt16BE(0);
        const names: string[] = [];
        let size = 40;
        for (let i = start; i < all.length; i++) {
          size += Buffer.byteLength(JSON.stringify(all[i])) + 1;
          if (size > LIST_REPLY_MAX) break;
          names.push(all[i]);
        }
        reply(MsgType.OK, seq, Buffer.from(JSON.stringify({ total: all.length, names })));
        return true;
      }
    }
    return true;
  }
}
