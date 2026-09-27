import { useState } from "react";
import type { DisplayGroup, DisplayItem, DisplaySecretResponse } from "../api/types";
import { useApiData } from "../api/useApiData";
import { POLL_LIVE_MS } from "../api/pollIntervals";
import { AsyncPanel } from "../design/AsyncPanel";
import { AppButton, AppSelect, Panel, StatTile } from "../design/components";
import { DisplayCard } from "./displays/DisplayCard";
import { DisplayForm, SecretPanel } from "./displays/DisplayForm";
import { GroupDeleteDialog, GroupNameDialog, GroupSection } from "./displays/DisplayGroups";
import { useCollapsedGroups } from "./displays/useCollapsedGroups";
import { DisplayPushDialog } from "./displays/DisplayPushDialog";
import { byBatteryFirst, type DisplaySource } from "./displays/displayUtil";

/**
 * Электронные QR-точки (ESP32 + e-paper, docs/displays.md): реестр, состояние каждой, команды. Отправка QR — отсюда («Повторить»)
 * и из Мастерской / карточки узла («На дисплей»); сервер сам рисует кадр и сам ходит к дисплеям.
 */
export function DisplaysScreen() {
  const { data: displays, error, reload } = useApiData<DisplayItem[]>("/api/displays", { pollMs: POLL_LIVE_MS });
  const { data: groups, reload: reloadGroups } = useApiData<DisplayGroup[]>("/api/display-groups", { pollMs: POLL_LIVE_MS });
  const [form, setForm] = useState<{ edit?: DisplayItem; groupId?: string } | null>(null);
  const [groupDialog, setGroupDialog] = useState<{ kind: "new" } | { kind: "rename" | "delete"; group: DisplayGroup } | null>(null);
  const [collapsed, toggleCollapsed] = useCollapsedGroups();
  const [secret, setSecret] = useState<DisplaySecretResponse | null>(null);
  const [push, setPush] = useState<{ source: DisplaySource; title: string } | null>(null);

  // Севшие — сверху: на игре мастер первым делом смотрит, куда бежать менять батарею.
  const [order, setOrder] = useState<"battery" | "id">("battery");

  const count = (s: DisplayItem["status"]) => (displays ?? []).filter((d) => d.status === s).length;
  const withBattery = (displays ?? []).filter((d) => d.battery !== null);
  const batteryCount = (l: DisplayItem["battery"]) => withBattery.filter((d) => d.battery === l).length;

  return (
    <div className="screen-grid">
      <p className="hint-text master-intro">
        Физические QR-точки: дисплей показывает тот же QR, что печатается, — игрок сканирует как обычно. Отправить QR на дисплей — кнопка «На дисплей» у
        готового QR в Мастерской или в карточке узла. Без сети дисплей продолжает показывать последний кадр.
      </p>
      <div className="stat-row">
        <StatTile label="на связи" value={count("ONLINE")} tone="ok" />
        <StatTile label="обновляются" value={count("UPDATING")} tone="accent" />
        <StatTile label="ошибка" value={count("ERROR")} tone="danger" />
        <StatTile label="нет связи" value={count("OFFLINE")} />
      </div>
      {withBattery.length > 0 && (
        <div className="stat-row">
          <StatTile label="батарея в норме" value={batteryCount("OK")} tone="ok" />
          <StatTile label="батарея: мало" value={batteryCount("LOW")} tone="money" />
          <StatTile label="батарея: критично" value={batteryCount("CRITICAL")} tone="danger" />
        </div>
      )}
      {secret && <SecretPanel result={secret} onClose={() => setSecret(null)} />}
      {form && (
        <DisplayForm
          key={form.edit?.id ?? `new-${form.groupId ?? ""}`}
          editing={form.edit}
          groups={groups ?? []}
          defaultGroupId={form.groupId}
          onCreated={(r) => {
            setForm(null);
            setSecret(r);
            reload();
            reloadGroups();
          }}
          onSaved={() => {
            setForm(null);
            reload();
            reloadGroups();
          }}
          onCancel={() => setForm(null)}
        />
      )}
      <Panel
        title={`Дисплеи${displays ? ` (${displays.length})` : ""}`}
        action={
          <span className="display-actions">
            <AppSelect value={order} onChange={(e) => setOrder(e.target.value as "battery" | "id")} aria-label="порядок">
              <option value="battery">сначала севшие</option>
              <option value="id">по номеру</option>
            </AppSelect>
            <AppButton onClick={() => setGroupDialog({ kind: "new" })}>+ группа</AppButton>
            <AppButton onClick={() => setForm({})}>+ дисплей</AppButton>
          </span>
        }
      >
        <AsyncPanel data={displays} error={error} isEmpty={(d) => d.length === 0} emptyLabel="дисплеев пока нет — добавьте первый">
          {(list) => {
            const sorted = order === "battery" ? [...list].sort(byBatteryFirst) : list;
            const cards = (items: DisplayItem[]) => (
              <div className="display-grid">
                {items.map((d) => (
                  <DisplayCard
                    key={d.id}
                    display={d}
                    groups={groups ?? []}
                    onChanged={() => {
                      reload();
                      reloadGroups();
                    }}
                    onEdit={() => setForm({ edit: d })}
                    onSecret={(r) => {
                      setSecret(r);
                      reload();
                    }}
                    onPush={(source, title) => setPush({ source, title })}
                  />
                ))}
              </div>
            );
            // Групп ещё нет — плоский список, как раньше.
            if (!groups || groups.length === 0) return cards(sorted);
            const known = new Set(groups.map((g) => g.id));
            const ungrouped = sorted.filter((d) => !d.groupId || !known.has(d.groupId));
            return (
              <div className="display-groups">
                {groups.map((g) => (
                  <GroupSection
                    key={g.id}
                    title={g.name}
                    group={g}
                    displays={sorted.filter((d) => d.groupId === g.id)}
                    collapsed={collapsed.has(g.id)}
                    onToggle={() => toggleCollapsed(g.id)}
                    onAdd={() => setForm({ groupId: g.id })}
                    onRename={() => setGroupDialog({ kind: "rename", group: g })}
                    onDelete={() => setGroupDialog({ kind: "delete", group: g })}
                  >
                    {cards(sorted.filter((d) => d.groupId === g.id))}
                  </GroupSection>
                ))}
                {ungrouped.length > 0 && (
                  <GroupSection title="Без группы" displays={ungrouped} collapsed={collapsed.has("")} onToggle={() => toggleCollapsed("")}>
                    {cards(ungrouped)}
                  </GroupSection>
                )}
              </div>
            );
          }}
        </AsyncPanel>
      </Panel>
      {groupDialog?.kind === "delete" && (
        <GroupDeleteDialog
          group={groupDialog.group}
          onCancel={() => setGroupDialog(null)}
          onDone={() => {
            setGroupDialog(null);
            reloadGroups();
            reload();
          }}
        />
      )}
      {groupDialog && groupDialog.kind !== "delete" && (
        <GroupNameDialog
          group={groupDialog.kind === "rename" ? groupDialog.group : undefined}
          onCancel={() => setGroupDialog(null)}
          onDone={() => {
            setGroupDialog(null);
            reloadGroups();
          }}
        />
      )}
      {push && (
        <DisplayPushDialog
          source={push.source}
          title={push.title}
          onClose={() => {
            setPush(null);
            reload();
          }}
        />
      )}
    </div>
  );
}
