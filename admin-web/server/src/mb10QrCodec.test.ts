import { test } from "node:test";
import assert from "node:assert/strict";
import { encodeContainerQr, encodeProvisionQr, encodeRamUpgradeQr, encodeShardQr } from "./lib/mb10QrCodec.js";
import { loadContract, type QrVectors } from "./contractVectors.js";

/**
 * mb10QrCodec.ts только кодирует (декодирует QR исключительно телефон игрока), поэтому проверка — по общим векторам `qr.json`
 * (посчитаны независимо; их же читает QrContractTest на Android): поля → строка, ровно та, что обязан разобрать телефон. Раньше здесь
 * лежала копия Kotlin-декодера как «эталон» — она старела молча; теперь эталон один и общий. SECALERT кодирует только приложение.
 */
const v = loadContract<QrVectors>("qr");

for (const c of v.containers) {
  test(`QR контейнера: ${c.name}`, () => {
    const slots = c.loot.map((l) => ({ typeName: l.type, tierLevel: l.tier, copies: l.copies, payload: l.payload }));
    assert.equal(encodeContainerQr(c.id, c.containerName, c.tier, c.ownerFaction, slots), c.line);
  });
}

for (const s of v.shards) {
  test(`QR шарда: ${s.name}`, () => {
    assert.equal(encodeShardQr(s.id, s.decryptAction, s.tier, s.valueHint, s.title, s.meta, s.body, s.moneyAmount), s.line);
  });
}

for (const r of v.ram) {
  test(`QR RAM-апгрейда: ${r.name}`, () => {
    assert.equal(encodeRamUpgradeQr(r.token, r.delta), r.line);
  });
}

for (const p of v.provisions) {
  test(`QR персонажа: ${p.name}`, () => {
    const qr = encodeProvisionQr({ id: p.id, url: p.collectorUrl, secret: p.gameSecret, callsign: p.callsign, faction: p.faction, balance: p.startBalance, ram: p.ramCapacity });
    assert.equal(qr, p.line);
  });
}

test("свободный текст с ':' и ';' в имени и фракции контейнера не ломает число сегментов (всё через base64)", () => {
  const qr = encodeContainerQr("nasos-5", "Название: с двоеточием; и точкой с запятой", 1, "Фракция:X", []);
  assert.equal(qr.split(":").length, 8);
});
