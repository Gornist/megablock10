import { AppInput, Field } from "../../design/components";
import { ToggleField } from "./common";

/** Состояние формы полей шарда — money хранится строкой ради контролируемого инпута, конвертируется в moneyAmount только на отправке. */
export interface ShardDraft {
  title: string;
  meta: string;
  body: string;
  valueHint: string;
  decryptAction: boolean;
  money: string;
}

export const EMPTY_SHARD_DRAFT: ShardDraft = { title: "", meta: "", body: "", valueHint: "", decryptAction: false, money: "0" };

export function shardDraftToPayload(d: ShardDraft) {
  return { title: d.title, meta: d.meta, body: d.body, valueHint: d.valueHint, decryptAction: d.decryptAction, moneyAmount: Number(d.money) || 0 };
}

/**
 * Общие 6 полей шарда (заголовок/мета/текст/подсказка ценности/взлом/деньги) —
 * раньше собирались вручную дважды: внутри слота контейнера и в форме
 * одиночного шарда. Теперь один компонент на оба случая.
 */
export function ShardFields({ value, onChange }: { value: ShardDraft; onChange: (patch: Partial<ShardDraft>) => void }) {
  return (
    <>
      <Field label="Заголовок">
        <AppInput value={value.title} onChange={(e) => onChange({ title: e.target.value })} placeholder="Служебный лог клиники" />
      </Field>
      <Field label="Мета-строка">
        <AppInput value={value.meta} onChange={(e) => onChange({ meta: e.target.value })} placeholder="получен 21:02 · клиника, уровень доступа 2" />
      </Field>
      <Field label="Текст шарда">
        <textarea
          className="app-input master-textarea"
          value={value.body}
          onChange={(e) => onChange({ body: e.target.value })}
          placeholder="Полный текст, который увидит игрок"
        />
      </Field>
      <Field label="Подсказка ценности">
        <AppInput value={value.valueHint} onChange={(e) => onChange({ valueHint: e.target.value })} placeholder="ценный технический документ" />
      </Field>
      <ToggleField label="требует взлома" value={value.decryptAction} onToggle={() => onChange({ decryptAction: !value.decryptAction })} />
      <Field label="Деньги в шарде, €$">
        <AppInput value={value.money} onChange={(e) => onChange({ money: e.target.value.replace(/\D/g, "") })} placeholder="0" />
      </Field>
    </>
  );
}
