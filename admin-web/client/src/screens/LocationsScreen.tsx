import { useState } from "react";
import { api } from "../api/client";
import type { AudioChannel, DisplayGroup, DisplayItem } from "../api/types";
import { POLL_LIVE_MS } from "../api/pollIntervals";
import { useAsyncAction } from "../api/useAsyncAction";
import { AsyncPanel } from "../design/AsyncPanel";
import { AppButton, AppSelect, Panel } from "../design/components";
import { navigate } from "../router";
import { PointAudioBlock, VolumeInput } from "./audio/PointAudio";
import { DeviceDetail } from "./displays/DeviceDetail";
import { DeviceStats } from "./displays/DeviceStats";
import { GroupDeleteDialog, GroupNameDialog, GroupSection } from "./displays/DisplayGroups";
import { StatusAndBattery } from "./displays/DeviceStatus";
import { byBatteryFirst } from "./displays/displayUtil";
import { useCollapsedGroups } from "./displays/useCollapsedGroups";
import { useDeviceData } from "./displays/useDeviceData";
import { useDeviceEditor } from "./displays/useDeviceEditor";

/**
 * Локации — точки на площадке по местам: локация сворачивается, в заголовке — её фон (канал и громкость), внутри — точки
 * со связью, батареей, узлом (если стоит узлом-контейнером) и своим фоном; «подробнее» — карточка точки с командами.
 * Точки без узла (просто динамик в баре) живут только здесь. Узел с его точкой — на экране «Узлы».
 */
export function LocationsScreen() {
  const data = useDeviceData({ groupsPollMs: POLL_LIVE_MS });
  const { displays, error, groups, channels, nodeName, reloadGroups, reloadAll } = data;
  const editor = useDeviceEditor(data);
  const [groupDialog, setGroupDialog] = useState<{ kind: "new" } | { kind: "rename" | "delete"; group: DisplayGroup } | null>(null);
  const [collapsed, toggleCollapsed] = useCollapsedGroups();
  const [open, setOpen] = useState<Set<string>>(new Set());
  // Севшие — сверху: на игре мастер первым делом смотрит, куда бежать менять батарею.
  const [order, setOrder] = useState<"battery" | "id">("battery");

  const toggleOpen = (id: string) =>
    setOpen((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });

  const points = (list: DisplayItem[]) => (
    <ul className="location-points">
      {list.map((d) => (
        <li key={d.id} className="location-point" data-point={d.id}>
          <div className="location-point-line">
            <button type="button" className="display-group-toggle" aria-expanded={open.has(d.id)} onClick={() => toggleOpen(d.id)}>
              <span className="display-group-caret">{open.has(d.id) ? "▾" : "▸"}</span>
              <span className="sound-point-name">{d.name}</span>
              <span className="hint-text mono">{d.id}</span>
            </button>
            {d.nodeId && (
              <button type="button" className="link-button" onClick={() => navigate("nodes", d.nodeId!)}>
                узел «{nodeName.get(d.nodeId) ?? d.nodeId}»
              </button>
            )}
            <StatusAndBattery d={d} />
          </div>
          {d.audio && <PointAudioBlock className="location-point-audio" point={d} channels={channels} onSaved={reloadAll} />}
          {open.has(d.id) && (
            <DeviceDetail display={d} {...editor.detailProps(d)} />
          )}
        </li>
      ))}
    </ul>
  );

  return (
    <div className="screen-grid">
      <p className="hint-text master-intro">
        Точки на площадке по локациям: QR-дисплей и звук. Фон локации меняется здесь за секунды; точка может играть своё поверх локации. Точка, стоящая
        узлом-контейнером, видна и в карточке узла.
      </p>
      <DeviceStats displays={displays ?? []} />
      {editor.secretPanel}
      {editor.formPanel}
      <Panel
        title={`Локации${displays ? ` · точек ${displays.length}` : ""}`}
        action={
          <span className="display-actions">
            <AppSelect value={order} onChange={(e) => setOrder(e.target.value as "battery" | "id")} aria-label="порядок">
              <option value="battery">сначала севшие</option>
              <option value="id">по номеру</option>
            </AppSelect>
            <AppButton onClick={() => setGroupDialog({ kind: "new" })}>+ локация</AppButton>
            <AppButton onClick={() => editor.openNew()}>+ точка</AppButton>
          </span>
        }
      >
        <AsyncPanel data={displays} error={error} isEmpty={(d) => d.length === 0 && groups.length === 0} emptyLabel="точек пока нет — добавьте первую">
          {(list) => {
            const sorted = order === "battery" ? [...list].sort(byBatteryFirst) : list;
            const known = new Set(groups.map((g) => g.id));
            const ungrouped = sorted.filter((d) => !d.groupId || !known.has(d.groupId));
            return (
              <div className="display-groups">
                {groups.map((g) => {
                  const members = sorted.filter((d) => d.groupId === g.id);
                  return (
                    <GroupSection
                      key={g.id}
                      title={g.name}
                      group={g}
                      displays={members}
                      collapsed={collapsed.has(g.id)}
                      onToggle={() => toggleCollapsed(g.id)}
                      onAdd={() => editor.openNew(g.id)}
                      onRename={() => setGroupDialog({ kind: "rename", group: g })}
                      onDelete={() => setGroupDialog({ kind: "delete", group: g })}
                      extra={<LocationAudio group={g} channels={channels} onSaved={reloadGroups} />}
                    >
                      {points(members)}
                    </GroupSection>
                  );
                })}
                {ungrouped.length > 0 && (
                  <GroupSection title="Без локации" displays={ungrouped} collapsed={collapsed.has("")} onToggle={() => toggleCollapsed("")}>
                    {points(ungrouped)}
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
            reloadAll();
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
    </div>
  );
}

/** Фон локации в её заголовке: канал (или тишина) и громкость (пусто — как у канала). */
function LocationAudio({ group: g, channels, onSaved }: { group: DisplayGroup; channels: AudioChannel[]; onSaved: () => void }) {
  const { error, run } = useAsyncAction({ fallbackError: "не удалось сохранить" });
  const save = (channelId: string | null, volume: number | null) =>
    run(() => api.put(`/api/display-groups/${encodeURIComponent(g.id)}/audio`, { channelId, volume })).then((r) => r.ok && onSaved());
  return (
    <span className="sound-controls" title="фон локации">
      <span className="hint-text">♪</span>
      <AppSelect aria-label={`канал группы ${g.name}`} value={g.audioChannelId ?? ""} onChange={(e) => void save(e.target.value || null, g.audioVolume)}>
        <option value="">— тишина —</option>
        {channels.map((c) => (
          <option key={c.id} value={c.id}>
            {c.name}
          </option>
        ))}
      </AppSelect>
      <VolumeInput
        key={`g-${g.audioVolume}`}
        label={`громкость группы ${g.name}`}
        value={g.audioVolume}
        placeholder="авто"
        onCommit={(v) => void save(g.audioChannelId, v)}
      />
      {error && <span className="login-error">{error}</span>}
    </span>
  );
}
