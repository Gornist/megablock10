import type { BridgeDoc } from "./bridgeProtocol.js";

/** Сообщение-поток изменений Моста (push `chg`): документ после изменения; удаление — с deleted и последней версией документа. */
export interface ChangePush {
  seq: number;
  /** false — транзакция ещё не закончилась, следующий кадр с тем же seq тоже её часть. Нет поля — как true. */
  last?: boolean;
  deleted?: boolean;
  doc: BridgeDoc;
}

/**
 * Копия документов Моста в памяти коллектора: снимок при подписке, дальше изменения пачками по сквозному seq. Операция с ценностью
 * трогает несколько документов одной транзакцией — кадры копятся до `last` и применяются разом, чтобы экран не увидел деку
 * без предметов. Обрыв — снимок заменяет всё (`replaceSnapshot`), а пока Моста нет, копию сбрасывают (`clear`): старое «как живое» не показываем.
 */
export class Mirror {
  private byType = new Map<string, Map<string, BridgeDoc>>();
  private batch: ChangePush[] = [];
  seq = 0;

  replaceSnapshot(docs: BridgeDoc[], seq: number): void {
    this.byType = new Map();
    this.batch = [];
    for (const d of docs) this.set(d);
    this.seq = seq;
  }

  /** Кадр потока изменений. Кадр с seq не больше уже применённого (повтор после снимка) отбрасывается. */
  apply(push: ChangePush): void {
    if (push.seq <= this.seq && this.batch.length === 0) return;
    this.batch.push(push);
    if (push.last === false) return;
    for (const p of this.batch) {
      if (p.deleted) this.byType.get(p.doc.type)?.delete(p.doc.id);
      else this.set(p.doc);
      this.seq = Math.max(this.seq, p.seq);
    }
    this.batch = [];
  }

  clear(): void {
    this.byType = new Map();
    this.batch = [];
    this.seq = 0;
  }

  get(type: string, id: string): BridgeDoc | undefined {
    return this.byType.get(type)?.get(id);
  }

  list(type: string): BridgeDoc[] {
    return [...(this.byType.get(type)?.values() ?? [])];
  }

  /** Все документы по типам — для снимка экрана. */
  all(): Record<string, BridgeDoc[]> {
    const out: Record<string, BridgeDoc[]> = {};
    for (const [type, docs] of this.byType) out[type] = [...docs.values()];
    return out;
  }

  private set(doc: BridgeDoc): void {
    let docs = this.byType.get(doc.type);
    if (!docs) this.byType.set(doc.type, (docs = new Map()));
    const prev = docs.get(doc.id);
    // Старее уже известной версии (запоздавший кадр) не применяем.
    if (!prev || doc.ver >= prev.ver) docs.set(doc.id, doc);
  }
}
