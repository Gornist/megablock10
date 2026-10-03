import { useState, type ComponentProps } from "react";
import type { DisplayItem, DisplaySecretResponse } from "../../api/types";
import type { DeviceDetail } from "./DeviceDetail";
import { DisplayForm, SecretPanel } from "./DisplayForm";
import type { useDeviceData } from "./useDeviceData";

/**
 * Форма точки («+ точка», «Изменить») и показ секрета (новая точка, «Новый секрет») — общие для «Устройств», «Локаций» и
 * точки узла: раньше каждый экран держал своё состояние формы и секрета и одинаково собирал пропсы карточки `DeviceDetail`.
 *
 * `secretPanel` и `formPanel` — рисовать там, где экран их показывал; `detailProps(d)` — всё для карточки, кроме самой точки.
 * После сохранения формы перечитывается `reloadAfterSave` (по умолчанию точки и локации: точка могла переехать),
 * после команды в карточке — `reloadAfterChange`.
 */
export function useDeviceEditor(
  data: ReturnType<typeof useDeviceData>,
  { reloadAfterSave = data.reloadAll, reloadAfterChange = data.reloadAll }: { reloadAfterSave?: () => void; reloadAfterChange?: () => void } = {},
) {
  const [form, setForm] = useState<{ edit?: DisplayItem; groupId?: string } | null>(null);
  const [secret, setSecret] = useState<DisplaySecretResponse | null>(null);

  const detailProps = (d: DisplayItem): Omit<ComponentProps<typeof DeviceDetail>, "display"> => ({
    groups: data.groups,
    channels: data.channels,
    nodes: data.namedNodes,
    takenNodes: data.takenNodes,
    onChanged: reloadAfterChange,
    onEdit: () => setForm({ edit: d }),
    onSecret: (r) => {
      setSecret(r);
      data.reload();
    },
  });

  const secretPanel = secret && <SecretPanel result={secret} onClose={() => setSecret(null)} />;
  const formPanel = form && (
    <DisplayForm
      key={form.edit?.id ?? `new-${form.groupId ?? ""}`}
      editing={form.edit}
      groups={data.groups}
      nodes={data.namedNodes}
      takenNodes={data.takenNodes}
      defaultGroupId={form.groupId}
      onCreated={(r) => {
        setForm(null);
        setSecret(r);
        data.reloadAll();
      }}
      onSaved={() => {
        setForm(null);
        reloadAfterSave();
      }}
      onCancel={() => setForm(null)}
    />
  );

  return {
    /** «+ точка»; из заголовка локации — сразу в неё. */
    openNew: (groupId?: string) => setForm(groupId ? { groupId } : {}),
    detailProps,
    secretPanel,
    formPanel,
  };
}
