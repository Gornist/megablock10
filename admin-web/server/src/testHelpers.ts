import assert from "node:assert/strict";
import { resetPresence } from "./lib/presence.js";
import { loginAs, testApp, testDb, testDevice, testMaster } from "./testUtil.js";

/** Общие помощники тестов управления игрой (правки, объявления, аналитика, события): мастер с сессией, игроки с данными, опрос телефона. */

export type App = ReturnType<typeof testApp>;
export type Device = ReturnType<typeof testDevice>;

export const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export async function setup() {
  resetPresence();
  const db = testDb();
  const app = testApp(db);
  const master = testMaster(db, "Мастер-1");
  const session = await loginAs(app, master.name, master.token);
  return { db, app, headers: { authorization: `Bearer ${session}` } };
}

export async function seedPlayer(app: App, opts: { callsign: string; faction: string; balance?: number; ram?: number }): Promise<Device> {
  const device = testDevice();
  const records = [
    device.change({ field: "callsign", newValue: opts.callsign, reason: "CHARACTER_CREATED" }),
    device.change({ field: "faction", newValue: opts.faction, reason: "CHARACTER_CREATED" }),
  ];
  if (opts.balance !== undefined) records.push(device.change({ field: "balance", oldValue: "0", newValue: String(opts.balance), reason: "BREACH_EDDIES" }));
  if (opts.ram !== undefined) records.push(device.change({ field: "ramCapacity", oldValue: "6", newValue: String(opts.ram), reason: "RAM_UPGRADE" }));
  const res = await app.inject({ method: "POST", url: "/api/changes", payload: { records } });
  assert.equal(res.json().rejected.length, 0, JSON.stringify(res.json().rejected));
  return device;
}

export async function players(app: App, headers: Record<string, string>) {
  return (await app.inject({ method: "GET", url: "/api/players", headers })).json() as {
    publicKeyB64: string;
    callsign: string;
    balance: number;
    ramCapacity: number;
    faction: string;
  }[];
}

export const poll = (app: App, device: Device, ackIds: string[] = []) =>
  app.inject({ method: "POST", url: "/api/changes", payload: { records: [], subjectKeyB64: device.publicKeyB64, ackIds } });
