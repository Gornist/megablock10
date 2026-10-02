import { FakeBridge } from "../net/fakeBridge.js";

/**
 * Мост-пустышка с примером «Сети» для разработки экрана без devbox (docs/netrun-bridge-protocol.md):
 *
 *   npm run fake-bridge [-- --port 7410 --key master-key]
 *
 * Дальше коллектор: BRIDGE_URL=ws://127.0.0.1:7410/netrun/v1 BRIDGE_MASTER_KEY=master-key npm run dev
 */
const arg = (name: string, fallback: string) => {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
};

const now = Date.now();
const bridge = new FakeBridge({
  port: Number(arg("port", "7410")),
  key: arg("key", "master-key"),
  docs: [
    { type: "settings", id: "global", data: { paused: false, venue_link: true, await_flatline: 1, await_timeout_s: 60, soft_ice_reentry_pause_s: 600 } },
    { type: "node", id: "node_00", data: { title: "Учебный узел", tier: "BASE", tutorial: true, lockdown_until: 0, eddies: 0 } },
    { type: "node", id: "node_07", data: { title: "Склад «Арасаки»", tier: "STANDARD", tutorial: false, lockdown_until: now + 5 * 60_000, eddies: 300 } },
    { type: "node", id: "node_09", data: { title: "Хранилище «Милитех»", tier: "NIGHTMARE", tutorial: false, lockdown_until: 0, eddies: 1200 } },
    { type: "node_cfg", id: "node_07", data: { paused: false, goal: { kind: "open", value: 120, deadline: now + 8 * 60_000, set_at: now, done: false, result: null } } },
    { type: "terminal", id: "t03", data: { label: "Подвал, стойка 3", node: "node_07", silent: false, battery: 71, fps: 72, link: "ok", beat_at: now - 4000 } },
    { type: "terminal", id: "t04", data: { label: "Бар, стойка 1", node: "node_09", silent: true, battery: 18, fps: 0, link: "lost", beat_at: now - 95_000 } },
    { type: "session", id: "s_9f2c41d07a3e5b60", data: { state: "active", terminal: "t03", node: "node_07", runner: "MFkwEwYH", callsign: "Призрак", confirmed_at: now - 120_000, loot_eddies: 40, outcome: null, finished_at: 0, world: { connected: true, trace: 42, level: "SUSPICIOUS" } } },
    { type: "deck", id: "s_9f2c41d07a3e5b60", data: { items: ["it_01aa", "it_02bb", "it_4c1a"], protected: "it_01aa" } },
    { type: "master_req", id: "flatline:s_aaaaaaaaaaaaaaaa", data: { kind: "flatline", ref: "s_aaaaaaaaaaaaaaaa", node: "node_09", summary: "ФЛЭТЛАЙН: Волна", state: "pending", default: "approve", expires_at: now + 45_000, decision: null } },
    { type: "alert", id: "al_a_3f9c1e07b2d4", data: { kind: "auditor_item_owner", msg: "it_02bb: владелец deck:s_9f2c, но сессия закрыта", items: ["it_02bb"] } },
    { type: "net_query", id: "nq_1", data: { runner: "Призрак", state: "open", messages: [{ mid: "m1", from: "runner", text: "Где шард?", at: now - 30_000 }] } },
    { type: "template", id: "tpl_night", data: { title: "Ночь: злее ICE", settings: { await_flatline: 1 }, node_cfg: { trace_per_s: 3 } } },
  ],
});
bridge.start().then((port) => console.log(`[fake-bridge] ${bridge.url} (порт ${port}), ключ роли master: ${arg("key", "master-key")}`));
