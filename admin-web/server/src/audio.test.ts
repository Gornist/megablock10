import { test } from "node:test";
import assert from "node:assert/strict";
import type { AnnounceResponse, AudioCatalogTrack, AudioChannel, AudioClip, DisplayGroup, DisplayItem, DisplaySecretResponse } from "./apiTypes.js";
import { buildApp } from "./app.js";
import { parseWav } from "./audio/wav.js";
import { DisplayManager } from "./displays/manager.js";
import { MockDisplay } from "./displays/mockDisplay.js";
import { secretKey } from "./displays/repository.js";
import { loginAs, testDb, testMaster } from "./testUtil.js";

const FAST = {
  connectTimeoutMs: 300,
  helloTimeoutMs: 200,
  receivedTimeoutMs: 300,
  displayedTimeoutMs: 300,
  commandTimeoutMs: 300,
  retryDelaysMs: [20, 20],
  probeIntervalMs: 0,
  log: () => {},
};

/** WAV PCM16 моно: ms миллисекунд тишины на rate Гц. */
function wav(ms: number, rate = 16000, tone = 0): Buffer {
  const samples = Math.round((rate * ms) / 1000);
  const b = Buffer.alloc(44 + samples * 2);
  b.write("RIFF", 0, "ascii");
  b.writeUInt32LE(36 + samples * 2, 4);
  b.write("WAVEfmt ", 8, "ascii");
  b.writeUInt32LE(16, 16);
  b.writeUInt16LE(1, 20);
  b.writeUInt16LE(1, 22);
  b.writeUInt32LE(rate, 24);
  b.writeUInt32LE(rate * 2, 28);
  b.writeUInt16LE(2, 32);
  b.writeUInt16LE(16, 34);
  b.write("data", 36, "ascii");
  b.writeUInt32LE(samples * 2, 40);
  for (let i = 0; i < samples; i++) b.writeInt16LE(tone ? Math.round(Math.sin(i / tone) * 8000) : 0, 44 + i * 2);
  return b;
}

async function waitFor(what: string, cond: () => boolean | Promise<boolean>, ms = 3000) {
  const until = Date.now() + ms;
  while (!(await cond())) {
    if (Date.now() > until) assert.fail(`не дождались: ${what}`);
    await new Promise((r) => setTimeout(r, 10));
  }
}

async function setup() {
  const db = testDb();
  const displays = new DisplayManager(db, FAST);
  const app = buildApp(db, { logger: false, displays });
  const master = testMaster(db, "Мастер-1");
  const headers = { authorization: `Bearer ${await loginAs(app, master.name, master.token)}` };
  const mocks: MockDisplay[] = [];

  async function addPoint(id: string, opts: { audio?: boolean; tracks?: string[]; groupId?: string } = {}) {
    const mock = new MockDisplay({
      deviceId: id,
      key: Buffer.alloc(32),
      width: 792,
      height: 272,
      displayDelayMs: 5,
      roles: opts.audio === false ? ["display"] : ["display", "audio"],
      tracks: opts.tracks ?? ["ad-neon.mp3", "radio-1.mp3", "rain.mp3"],
      announceSpeed: 0.1,
    });
    const port = await mock.start();
    const res = await app.inject({
      method: "POST",
      url: "/api/displays",
      headers,
      payload: { id, name: `Точка ${id}`, ip: "127.0.0.1", port, groupId: opts.groupId ?? null },
    });
    assert.equal(res.statusCode, 200, res.body);
    (mock.options as { key: Buffer }).key = secretKey({ secret: (res.json() as DisplaySecretResponse).secret });
    mocks.push(mock);
    return mock;
  }

  // displays.probe молча пропускает опрос, пока у точки идёт операция (досылка состояния, LIST): на медленном раннере CI
  // сессия прошлой операции ещё не закрыта — HELLO не было, и проверка «после HELLO» читает старое. Ждём, пока опрос примут.
  const probe = async (id: string) => {
    const until = Date.now() + 3000;
    for (;;) {
      const run = displays.probe(id);
      if (run) return run;
      if (Date.now() > until) assert.fail(`точка ${id} занята — опрос не принят`);
      await new Promise((r) => setTimeout(r, 10));
    }
  };
  const get = async (id: string) => (await app.inject({ method: "GET", url: `/api/displays/${id}`, headers })).json() as DisplayItem;
  const cleanup = async () => {
    await app.close();
    await Promise.all(mocks.map((m) => m.stop()));
  };
  return { db, app, headers, displays, addPoint, probe, get, cleanup };
}

test("wav: PCM16 и IMA ADPCM моно — длительность; стерео и 8 бит — отказ", () => {
  assert.equal(parseWav(wav(1500))!.durationMs, 1500);
  const stereo = wav(100);
  stereo.writeUInt16LE(2, 22);
  assert.equal(parseWav(stereo), null);
  const pcm8 = wav(100);
  pcm8.writeUInt16LE(8, 34);
  assert.equal(parseWav(pcm8), null);
  assert.equal(parseWav(Buffer.from("not a wav at all, definitely not RIFF............")), null);
  // IMA ADPCM: блок 256 байт = 4 заголовка + 252 × 2 сэмпла + 1 = 505 сэмплов.
  const adpcm = Buffer.alloc(48 + 8 + 256 * 32);
  adpcm.write("RIFF", 0, "ascii");
  adpcm.writeUInt32LE(adpcm.length - 8, 4);
  adpcm.write("WAVEfmt ", 8, "ascii");
  adpcm.writeUInt32LE(20, 16);
  adpcm.writeUInt16LE(0x11, 20);
  adpcm.writeUInt16LE(1, 22);
  adpcm.writeUInt32LE(16000, 24);
  adpcm.writeUInt32LE(8110, 28);
  adpcm.writeUInt16LE(256, 32);
  adpcm.writeUInt16LE(4, 34);
  adpcm.writeUInt16LE(2, 36);
  adpcm.writeUInt16LE(505, 38);
  adpcm.write("data", 40, "ascii");
  adpcm.writeUInt32LE(256 * 32, 44);
  assert.equal(parseWav(adpcm)!.durationMs, Math.round(((505 * 32) / 16000) * 1000));
});

test("без сессии мастера — 401 на звук", async () => {
  const { app, cleanup } = await setup();
  try {
    for (const [method, url] of [
      ["GET", "/api/audio/channels"],
      ["POST", "/api/audio/channels"],
      ["GET", "/api/audio/clips"],
      ["POST", "/api/audio/clips"],
      ["POST", "/api/audio/announce"],
      ["PUT", "/api/displays/x/audio"],
      ["PUT", "/api/display-groups/x/audio"],
    ] as const) {
      assert.equal((await app.inject({ method, url })).statusCode, 401, `${method} ${url}`);
    }
  } finally {
    await cleanup();
  }
});

test("фон: канал группы доходит до звуковой точки; исключение точки и тишина; дисплей без звука не трогается", async () => {
  const { app, headers, displays, addPoint, probe, get, cleanup } = await setup();
  try {
    const group = (await app.inject({ method: "POST", url: "/api/display-groups", headers, payload: { name: "Бар «Посмертие»" } })).json() as DisplayGroup;
    const bar = await addPoint("bar-1", { groupId: group.id });
    const plain = await addPoint("qr-only", { audio: false, groupId: group.id });
    // Первый HELLO: сервер узнаёт, что точка звуковая, и шлёт её состояние (пока — тишина).
    await probe("bar-1");
    await probe("qr-only");
    await waitFor("первое состояние", () => bar.audioVersion >= 1);
    assert.deepEqual(bar.audioState!.tracks, []);
    assert.equal((await get("qr-only")).audio, null, "без роли audio звуковых полей нет");
    assert.deepEqual((await get("bar-1")).roles, ["display", "audio"]);

    const bad = await app.inject({ method: "POST", url: "/api/audio/channels", headers, payload: { name: "Радио", tracks: ["../etc/passwd"] } });
    assert.equal(bad.statusCode, 400);
    const ch = (
      await app.inject({
        method: "POST",
        url: "/api/audio/channels",
        headers,
        payload: { name: "Радио «Неон»", tracks: ["radio-1.mp3", "ad-neon.mp3", "lost.mp3"], shuffle: true, volume: 55 },
      })
    ).json() as AudioChannel;
    assert.equal((await app.inject({ method: "POST", url: "/api/audio/channels", headers, payload: { name: "радио «неон»", tracks: [] } })).statusCode, 409);

    const g = await app.inject({ method: "PUT", url: `/api/display-groups/${group.id}/audio`, headers, payload: { channelId: ch.id, volume: 70 } });
    assert.equal(g.statusCode, 200, g.body);
    await waitFor("канал группы на точке", () => bar.audioState?.tracks.length === 3);
    assert.equal(bar.audioState!.volume, 70, "громкость группы важнее громкости канала");
    assert.equal(plain.audioVersion, 0, "дисплею без звука звуковые команды не шлются");

    await probe("bar-1");
    let item = await get("bar-1");
    assert.equal(item.audio!.channelName, "Радио «Неон»");
    assert.equal(item.audio!.source, "group");
    assert.equal(item.audio!.applied, true);
    assert.deepEqual(item.audio!.missing, ["lost.mp3"], "трек канала, которого нет на карте");

    // Исключение: эта точка молчит, хотя у группы канал.
    const v = bar.audioVersion;
    assert.equal((await app.inject({ method: "PUT", url: "/api/displays/bar-1/audio", headers, payload: { channelId: "", volume: null } })).statusCode, 200);
    await waitFor("тишина на точке", () => bar.audioVersion > v);
    assert.deepEqual(bar.audioState!.tracks, []);
    item = await get("bar-1");
    assert.equal(item.audio!.source, "override");
    assert.equal(item.audio!.channelId, null);

    // Вернуть «как у группы»; удалить канал — группа уходит в тишину.
    await app.inject({ method: "PUT", url: "/api/displays/bar-1/audio", headers, payload: { channelId: null } });
    await waitFor("снова канал группы", () => bar.audioState?.tracks.length === 3);
    assert.equal((await app.inject({ method: "DELETE", url: `/api/audio/channels/${ch.id}`, headers })).statusCode, 200);
    await waitFor("канал удалён — тишина", () => bar.audioState?.tracks.length === 0);
    const groups = (await app.inject({ method: "GET", url: "/api/display-groups", headers })).json() as DisplayGroup[];
    assert.equal(groups[0].audioChannelId, null);
  } finally {
    await cleanup();
  }
});

test("точка перезагрузилась и забыла состояние — после HELLO сервер досылает; каталог треков — по LIST", async () => {
  const { app, headers, displays, addPoint, probe, get, cleanup } = await setup();
  try {
    const many = Array.from({ length: 70 }, (_, i) => `ambient-${String(i).padStart(2, "0")}-cyberpunk-city-at-night.mp3`);
    const p = await addPoint("hall", { tracks: many });
    const ch = (
      await app.inject({ method: "POST", url: "/api/audio/channels", headers, payload: { name: "Город", tracks: many.slice(0, 5) } })
    ).json() as AudioChannel;
    await probe("hall");
    await app.inject({ method: "PUT", url: "/api/displays/hall/audio", headers, payload: { channelId: ch.id, volume: 40 } });
    await waitFor("канал точки", () => p.audioState?.tracks.length === 5);
    const version = p.audioVersion;

    // Каталог длиннее одного ответа LIST (1 КБ) — сервер дочитывает страницами.
    await waitFor("каталог", () => (displays.repo.get("hall")?.audio_catalog ?? "").includes("ambient-69"));
    const catalog = (await app.inject({ method: "GET", url: "/api/audio/catalog", headers })).json() as AudioCatalogTrack[];
    assert.equal(catalog.length, 70);
    assert.equal(catalog[0].points, 1);

    // Перезагрузка без сохранённого состояния: HELLO с v=0.
    p.audioVersion = 0;
    p.audioState = null;
    await probe("hall");
    await waitFor("досылка после HELLO", () => p.audioVersion === version && p.audioState?.tracks.length === 5);
    await probe("hall");
    assert.equal((await get("hall")).audio!.applied, true);
  } finally {
    await cleanup();
  }
});

test("две правки фона подряд: вторая доходит, хотя первая ещё в пути", async () => {
  const { app, headers, addPoint, probe, cleanup } = await setup();
  try {
    const p = await addPoint("stage");
    await probe("stage");
    await waitFor("первое состояние", () => p.audioVersion >= 1);
    const put = (volume: number) => app.inject({ method: "PUT", url: "/api/displays/stage/audio", headers, payload: { channelId: "", volume } });
    // Точка приняла громкость 30, а сервер ещё ждёт её OK — вторая правка в это время не должна потеряться до следующего опроса.
    p.faults.audioStateReplyDelayMs = 300;
    assert.equal((await put(30)).statusCode, 200);
    await waitFor("первая правка на точке", () => p.audioState?.volume === 30);
    assert.equal((await put(80)).statusCode, 200);
    await waitFor("последняя правка на точке", () => p.audioState?.volume === 80);
  } finally {
    await cleanup();
  }
});

test("громкая связь: клип докачивается после обрыва, играет, «доиграло» — по HELLO; повтор того же клипа не грузится заново", async () => {
  const { app, headers, displays, addPoint, probe, get, cleanup } = await setup();
  try {
    const group = (await app.inject({ method: "POST", url: "/api/display-groups", headers, payload: { name: "Площадь" } })).json() as DisplayGroup;
    const a = await addPoint("sq-1", { groupId: group.id });
    const b = await addPoint("sq-2", { groupId: group.id });
    await addPoint("qr-only", { audio: false, groupId: group.id });
    for (const id of ["sq-1", "sq-2", "qr-only"]) await probe(id);

    const data = wav(1500, 16000, 7); // 48 КБ — три куска
    const bad = await app.inject({ method: "POST", url: "/api/audio/clips", headers, payload: { name: "x", data: Buffer.from("junk").toString("base64") } });
    assert.equal(bad.statusCode, 400);
    const clip = (
      await app.inject({ method: "POST", url: "/api/audio/clips", headers, payload: { name: "Игра началась", data: data.toString("base64"), preset: true } })
    ).json() as AudioClip;
    assert.equal(clip.durationMs, 1500);
    assert.equal(clip.preset, true);
    const clips = (await app.inject({ method: "GET", url: "/api/audio/clips", headers })).json() as AudioClip[];
    assert.equal(clips.length, 1);
    const played = await app.inject({ method: "GET", url: `/api/audio/clips/${clip.id}/data`, headers });
    assert.equal(played.headers["content-type"], "audio/wav");
    assert.equal(played.rawPayload.length, data.length);

    a.faults.dropMidClip = 1; // Wi-Fi пропал посреди загрузки
    const res = await app.inject({
      method: "POST",
      url: "/api/audio/announce",
      headers,
      payload: { targets: { groupIds: [group.id] }, clipId: clip.id, volume: 90 },
    });
    assert.equal(res.statusCode, 200, res.body);
    const ann = res.json() as AnnounceResponse;
    assert.deepEqual(ann.results.map((r) => r.displayId).sort(), ["sq-1", "sq-2"], "дисплей без звука в группе молча пропускается");
    await waitFor("обе играют", () => a.announcement?.state === "playing" && b.announcement?.state === "playing");
    assert.equal(a.announcement!.id, ann.id);
    assert.equal(a.faults.dropMidClip, 0, "обрыв посреди загрузки случился");
    assert.ok(a.clips.has(clip.id), "клип докачан после обрыва");
    // Точка играет с момента CLIP_COMMIT, а фазу сервер ставит по её OK — чуть позже.
    await waitFor("фаза PLAYING на сервере", async () => (await get("sq-1")).audio!.announce!.phase === "PLAYING");

    await waitFor("доиграли", () => a.announcement?.state === "done" && b.announcement?.state === "done");
    await probe("sq-1");
    const done = (await get("sq-1")).audio!.announce!;
    assert.equal(done.phase, "DONE");
    assert.equal(done.uploadedPct, 100);

    // Второй раз — CLIP_BEGIN скажет «уже есть», кусков не будет: проверим, что обрыв посреди загрузки не сработал.
    b.faults.dropMidClip = 1;
    const again = (
      await app.inject({ method: "POST", url: "/api/audio/announce", headers, payload: { targets: { displayIds: ["sq-2"] }, clipId: clip.id } })
    ).json() as AnnounceResponse;
    await waitFor("снова играет", () => b.announcement?.id === again.id && b.announcement.state === "playing");
    assert.equal(b.faults.dropMidClip, 1, "кусков не слали");

    // Стоп.
    const stop = await app.inject({ method: "POST", url: "/api/audio/announce/stop", headers, payload: { targets: { displayIds: ["sq-2"] } } });
    assert.equal(stop.statusCode, 200);
    await waitFor("остановлено", () => b.announcement?.state === "stopped");
    await waitFor("фаза STOPPED на сервере", async () => (await get("sq-2")).audio!.announce!.phase === "STOPPED");

    const unknown = await app.inject({ method: "POST", url: "/api/audio/announce", headers, payload: { targets: { all: true }, clipId: "0".repeat(64) } });
    assert.equal(unknown.statusCode, 404);
    const noTargets = await app.inject({ method: "POST", url: "/api/audio/announce", headers, payload: { targets: {}, clipId: clip.id } });
    assert.equal(noTargets.statusCode, 400);
  } finally {
    await cleanup();
  }
});
