import { useState, type ReactNode } from "react";
import { api } from "../../api/client";
import type { DisplayGroup, DisplayItem } from "../../api/types";
import { useAsyncAction } from "../../api/useAsyncAction";
import { AppButton, AppDialog, AppInput, Badge } from "../../design/components";

/**
 * Группа дисплеев сворачивающимся списком. В заголовке — то, что нужно видеть и свёрнутым: сколько точек, сколько на связи,
 * есть ли севшие батареи и ошибки; справа — переименовать / удалить (у «Без группы» их нет).
 */
export function GroupSection({
  title,
  group,
  displays,
  collapsed,
  onToggle,
  onRename,
  onDelete,
  onAdd,
  children,
}: {
  title: string;
  group?: DisplayGroup;
  displays: DisplayItem[];
  collapsed: boolean;
  onToggle: () => void;
  onRename?: () => void;
  onDelete?: () => void;
  onAdd?: () => void;
  children: ReactNode;
}) {
  const online = displays.filter((d) => d.status === "ONLINE" || d.status === "UPDATING").length;
  const critical = displays.filter((d) => d.battery === "CRITICAL").length;
  const low = displays.filter((d) => d.battery === "LOW").length;
  const errors = displays.filter((d) => d.status === "ERROR").length;
  return (
    <section className={`display-group${collapsed ? " collapsed" : ""}`} data-group={group?.id ?? "none"}>
      <header className="display-group-head">
        <button type="button" className="display-group-toggle" aria-expanded={!collapsed} onClick={onToggle}>
          <span className="display-group-caret">{collapsed ? "▸" : "▾"}</span>
          <span className="display-group-title">{title}</span>
          <span className="hint-text">
            {displays.length} · на связи {online}/{displays.length}
          </span>
        </button>
        <span className="display-group-flags">
          {errors > 0 && <Badge tone="danger">ошибка: {errors}</Badge>}
          {critical > 0 && <Badge tone="danger">батарея: {critical} критично</Badge>}
          {low > 0 && <Badge tone="warn">батарея: {low} мало</Badge>}
        </span>
        <span className="display-group-actions">
          {onAdd && <AppButton onClick={onAdd}>+ дисплей</AppButton>}
          {onRename && <AppButton onClick={onRename}>Переименовать</AppButton>}
          {onDelete && (
            <AppButton variant="danger" onClick={onDelete}>
              Удалить группу
            </AppButton>
          )}
        </span>
      </header>
      {!collapsed && (displays.length > 0 ? children : <p className="hint-text display-group-empty">в группе пока нет дисплеев</p>)}
    </section>
  );
}

/** Создать группу или переименовать: одно поле — название (например, локация «Бар «Посмертие»»). */
export function GroupNameDialog({ group, onDone, onCancel }: { group?: DisplayGroup; onDone: () => void; onCancel: () => void }) {
  const [name, setName] = useState(group?.name ?? "");
  const { busy, error, run } = useAsyncAction({ fallbackError: "не удалось сохранить группу" });
  async function save() {
    const res = await run(() =>
      group ? api.put<DisplayGroup>(`/api/display-groups/${encodeURIComponent(group.id)}`, { name }) : api.post<DisplayGroup>("/api/display-groups", { name }),
    );
    if (res.ok) onDone();
  }
  return (
    <AppDialog
      title={group ? `Переименовать «${group.name}»` : "Новая группа дисплеев"}
      confirmText={busy ? "Сохраняю…" : group ? "Переименовать" : "Создать"}
      confirmDisabled={busy || !name.trim()}
      onConfirm={save}
      onCancel={onCancel}
    >
      <div className="master-form">
        <label className="status-caps">Название (локация)</label>
        <AppInput autoFocus value={name} maxLength={64} onChange={(e) => setName(e.target.value)} placeholder="Бар «Посмертие»" />
        {error && <div className="login-error">{error}</div>}
      </div>
    </AppDialog>
  );
}

/** Удалить группу: её дисплеи остаются, становятся «без группы». */
export function GroupDeleteDialog({ group, onDone, onCancel }: { group: DisplayGroup; onDone: () => void; onCancel: () => void }) {
  const { busy, error, run } = useAsyncAction({ fallbackError: "не удалось удалить группу" });
  async function remove() {
    const res = await run(() => api.delete(`/api/display-groups/${encodeURIComponent(group.id)}`));
    if (res.ok) onDone();
  }
  return (
    <AppDialog
      title={`Удалить группу «${group.name}»?`}
      body={`Дисплеи группы (${group.count}) не удаляются — они окажутся «без группы».`}
      confirmText={busy ? "Удаляю…" : "Удалить"}
      confirmVariant="danger"
      confirmDisabled={busy}
      onConfirm={remove}
      onCancel={onCancel}
    >
      {error && <div className="login-error">{error}</div>}
    </AppDialog>
  );
}
