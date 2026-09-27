import { useState } from "react";
import { api } from "../api/client";
import type { AudioChannel, DisplayGroup, DisplayItem, DisplaySecretResponse, NodeSummary } from "../api/types";
import { POLL_LIVE_MS, POLL_RELAXED_MS } from "../api/pollIntervals";
import { useApiData } from "../api/useApiData";
import { useAsyncAction } from "../api/useAsyncAction";
import { AsyncPanel } from "../design/AsyncPanel";
import { AppButton, AppSelect, Badge, Panel, StatTile } from "../design/components";
import { navigate } from "../router";
import { PointAnnounce, PointAudioControls, PointAudioStatus, VolumeInput } from "./audio/PointAudio";
import { BatteryGauge } from "./displays/BatteryGauge";
import { DisplayCard } from "./displays/DisplayCard";
import { DisplayForm, SecretPanel } from "./displays/DisplayForm";
import { GroupDeleteDialog, GroupNameDialog, GroupSection } from "./displays/DisplayGroups";
import { DisplayPushDialog } from "./displays/DisplayPushDialog";
import { byBatteryFirst, STATUS_LABEL, STATUS_TONE, type DisplaySource } from "./displays/displayUtil";
import { useCollapsedGroups } from "./displays/useCollapsedGroups";

/**
 * Локации — точки на площадке по местам: локация сворачивается, в заголовке — её фон (канал и громкость), внутри — точки
 * со связью, батареей, узлом (если стоит узлом-контейнером) и своим фоном; «подробнее» — карточка точки с командами.
 * Точки без узла (просто динамик в баре) живут только здесь. Узел с его точкой — на экране «Узлы».
 */
export function LocationsScreen() {
  const { data: displays, error, reload } = useApiData<DisplayItem[]>("/api/displays", { pollMs: POLL_LIVE_MS });
  const { data: groups, reload: reloadGroups } = useApiData<DisplayGroup[]>("/api/display-groups", { pollMs: POLL_LIVE_MS });
  const { data: channels } = useApiData<AudioChannel[]>("/api/audio/channels", { pollMs: POLL_RELAXED_MS });
  const { data: nodes } = useApiData<NodeSummary[]>("/api/nodes", { pollMs: POLL_RELAXED_MS });
  const [form, setForm] = useState<{ edit?: DisplayItem; groupId?: string } | null>(null);
  const [groupDialog, setGroupDialog] = useState<{ kind: "new" } | { kind: "rename" | "delete"; group: DisplayGroup } | null>(null);
  const [collapsed, toggleCollapsed] = useCollapsedGroups();
  const [open, setOpen] = useState<Set<string>>(new Set());
  const [secret, setSecret] = useState<DisplaySecretResponse | null>(null);
  const [push, setPush] = useState<{ source: DisplaySource; title: string } | null>(null);
  // Севшие — сверху: на игре мастер первым делом смотрит, куда бежать менять батарею.
  const [order, setOrder] = useState<"battery" | "id">("battery");

  const reloadAll = () => {
    reload();
    reloadGroups();
  };
  const count = (s: DisplayItem["status"]) => (displays ?? []).filter((d) => d.status === s).length;
  const withBattery = (displays ?? []).filter((d) => d.battery !== null);
  const batteryCount = (l: DisplayItem["battery"]) => withBattery.filter((d) => d.battery === l).length;
  const nodeName = new Map((nodes ?? []).map((n) => [n.id, n.name]));
  const takenNodes = new Map((displays ?? []).filter((d) => d.nodeId).map((d) => [d.nodeId!, d.id]));
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
            <span className="display-card-status">
              <Badge tone={STATUS_TONE[d.status]}>{STATUS_LABEL[d.status]}</Badge>
              <BatteryGauge d={d} />
            </span>
          </div>
          {d.audio && (
            <div className="location-point-audio">
              <PointAudioStatus point={d} />
              <PointAudioControls point={d} channels={channels ?? []} onSaved={reloadAll} />
              <PointAnnounce point={d} />
            </div>
          )}
          {open.has(d.id) && (
            <DisplayCard
              display={d}
              groups={groups ?? []}
              onChanged={reloadAll}
              onEdit={() => setForm({ edit: d })}
              onSecret={(r) => {
                setSecret(r);
                reload();
              }}
              onPush={(source, title) => setPush({ source, title })}
            />
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
          nodes={(nodes ?? []).map((n) => ({ id: n.id, name: n.name }))}
          takenNodes={takenNodes}
          defaultGroupId={form.groupId}
          onCreated={(r) => {
            setForm(null);
            setSecret(r);
            reloadAll();
          }}
          onSaved={() => {
            setForm(null);
            reloadAll();
          }}
          onCancel={() => setForm(null)}
        />
      )}
      <Panel
        title={`Локации${displays ? ` · точек ${displays.length}` : ""}`}
        action={
          <span className="display-actions">
            <AppSelect value={order} onChange={(e) => setOrder(e.target.value as "battery" | "id")} aria-label="порядок">
              <option value="battery">сначала севшие</option>
              <option value="id">по номеру</option>
            </AppSelect>
            <AppButton onClick={() => setGroupDialog({ kind: "new" })}>+ локация</AppButton>
            <AppButton onClick={() => setForm({})}>+ точка</AppButton>
          </span>
        }
      >
        <AsyncPanel data={displays} error={error} isEmpty={(d) => d.length === 0 && (groups ?? []).length === 0} emptyLabel="точек пока нет — добавьте первую">
          {(list) => {
            const sorted = order === "battery" ? [...list].sort(byBatteryFirst) : list;
            const known = new Set((groups ?? []).map((g) => g.id));
            const ungrouped = sorted.filter((d) => !d.groupId || !known.has(d.groupId));
            return (
              <div className="display-groups">
                {(groups ?? []).map((g) => {
                  const members = sorted.filter((d) => d.groupId === g.id);
                  return (
                    <GroupSection
                      key={g.id}
                      title={g.name}
                      group={g}
                      displays={members}
                      collapsed={collapsed.has(g.id)}
                      onToggle={() => toggleCollapsed(g.id)}
                      onAdd={() => setForm({ groupId: g.id })}
                      onRename={() => setGroupDialog({ kind: "rename", group: g })}
                      onDelete={() => setGroupDialog({ kind: "delete", group: g })}
                      extra={<LocationAudio group={g} channels={channels ?? []} onSaved={reloadGroups} />}
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
