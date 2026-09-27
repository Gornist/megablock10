import { spawn, type ChildProcess } from "node:child_process";
import { readFileSync } from "node:fs";
import { createServer, type AddressInfo } from "node:net";
import { join } from "node:path";
import { inflateSync } from "node:zlib";

/**
 * Прошивка дисплея, собранная для ПК (firmware/display, `display_host`), как дочерний процесс: запуск с ожиданием «listening on»,
 * журнал, остановка, кадр «панели». Общее для сквозных тестов (firmwareHost.test.ts) и нагрузки (scripts/displayLoad.ts).
 */

/** Свободный TCP-порт на 127.0.0.1 (занять и сразу отпустить). */
export async function freePort(): Promise<number> {
  const s = createServer();
  await new Promise<void>((r) => s.listen(0, "127.0.0.1", () => r()));
  const port = (s.address() as AddressInfo).port;
  await new Promise<void>((r) => s.close(() => r()));
  return port;
}

export interface FirmwareHostOptions {
  bin: string;
  id: string;
  secret: string;
  port: number;
  /** Каталог «flash» и PNG «панели». */
  out: string;
  /** Флаги, с которыми процесс запускается всегда (--delay, таймауты…); разовые — в start(extra). */
  args?: string[];
}

export class FirmwareHostProcess {
  proc!: ChildProcess;
  /** Журнал всех запусков подряд (stderr прошивки). */
  log = "";

  constructor(readonly options: FirmwareHostOptions) {}

  get id(): string {
    return this.options.id;
  }
  get secret(): string {
    return this.options.secret;
  }
  get port(): number {
    return this.options.port;
  }
  get out(): string {
    return this.options.out;
  }

  /** Запустить и дождаться «listening on» (после загрузки кадра из «flash»). */
  async start(extra: string[] = [], timeoutMs = 5000): Promise<void> {
    const from = this.log.length;
    const o = this.options;
    this.proc = spawn(o.bin, ["--id", o.id, "--secret", o.secret, "--host", "127.0.0.1", "--port", String(o.port), "--out", o.out, ...(o.args ?? []), ...extra], {
      stdio: ["ignore", "ignore", "pipe"],
    });
    this.proc.stderr!.on("data", (d: Buffer) => (this.log += d.toString()));
    await this.waitLog(/listening on/, timeoutMs, from);
  }

  /** Ждать строки журнала, появившейся после позиции from (журнал копится между перезапусками). */
  async waitLog(re: RegExp, timeoutMs: number, from = 0): Promise<void> {
    const deadline = Date.now() + timeoutMs;
    while (!re.test(this.log.slice(from))) {
      // Только по времени: после выхода процесса его stderr ещё может дочитываться.
      if (Date.now() > deadline) throw new Error(`${this.id}: нет ${re} в журнале прошивки:\n${this.log}`);
      await new Promise((r) => setTimeout(r, 10));
    }
  }

  get exited(): boolean {
    return this.proc.exitCode !== null || this.proc.signalCode !== null;
  }

  async stop(): Promise<void> {
    if (!this.proc || this.exited) return;
    const done = new Promise((r) => this.proc.once("exit", r));
    this.proc.kill("SIGCONT"); // остановленный SIGSTOP иначе не умрёт до продолжения
    this.proc.kill("SIGKILL");
    await done;
  }

  /** Кадр «панели» — PNG, который пишет прошивка, назад в 1-битный кадр (1 — чёрный). */
  panelFrame(width: number, height: number): Buffer {
    const png = readFileSync(join(this.out, `${this.id}.png`));
    let off = 8;
    const idat: Buffer[] = [];
    while (off < png.length) {
      const len = png.readUInt32BE(off);
      const type = png.toString("ascii", off + 4, off + 8);
      if (type === "IDAT") idat.push(png.subarray(off + 8, off + 8 + len));
      off += 12 + len;
    }
    const raw = inflateSync(Buffer.concat(idat));
    const stride = Math.ceil(width / 8);
    const frame = Buffer.alloc(stride * height);
    for (let y = 0; y < height; y++) for (let i = 0; i < stride; i++) frame[y * stride + i] = ~raw[y * (stride + 1) + 1 + i] & 0xff;
    return frame;
  }
}
