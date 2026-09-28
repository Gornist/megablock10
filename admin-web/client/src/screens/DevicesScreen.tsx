import { useMemo, useState } from "react";
import type { AudioChannel, DisplayGroup, DisplayItem, DisplaySecretResponse, DisplayStatus, NodeSummary } from "../api/types";
import { POLL_LIVE_MS, POLL_RELAXED_MS } from "../api/pollIntervals";
import { useApiData } from "../api/useApiData";
import { AsyncPanel } from "../design/AsyncPanel";
import { AppButton, AppInput, AppSelect, Badge, Panel, StatTile } from "../design/components";
import { DataTable, type Column } from "../design/DataTable";
import { navigate } from "../router";
import { BatteryGauge } from "./displays/BatteryGauge";
import { DeviceDetail } from "./displays/DeviceDetail";
import { DisplayForm, SecretPanel } from "./displays/DisplayForm";
import { byBatteryFirst, STATUS_LABEL, STATUS_TONE } from "./displays/displayUtil";

const STATUS_FILTERS: { value: DisplayStatus | ""; label: string }[] = [
  { value: "", label: "любая связь" },
  { value: "ONLINE", label: "на связи" },
  { value: "OFFLINE", label: "нет связи" },
  { value: "UPDATING", label: "обновляется" },
  { value: "ERROR", label: "ошибка" },
  { value: "DISABLED", label: "выключен" },
];

/**
 * Устройства — плоский список всех физических точек (ESP32 + e-paper + звук), без привязки к локации или узлу: раньше
 * полное состояние и управление были только внутри «Локаций» (разворот строки), а в карточке узла — урезанная копия.
 * Здесь — один список «вот мои N коробок, вот их состояние», строка ведёт в ту же канонiчную карточку (`DeviceDetail`),
 * что и на «Локациях»/«Узлах».
 */
export function DevicesScreen({ deviceId }: { deviceId?: string }) {
  const { data: displays, error, reload } = useApiData<DisplayItem[]>("/api/displays", { pollMs: POLL_LIVE_MS });
  const { data: groups, reload: reloadGroups } = useApiData<DisplayGroup[]>("/api/display-groups", { pollMs: POLL_RELAXED_MS });
  const { data: channels } = useApiData<AudioChannel[]>("/api/audio/channels", { pollMs: POLL_RELAXED_MS });
  const { data: nodes } = useApiData<NodeSummary[]>("/api/nodes", { pollMs: POLL_RELAXED_MS });
  const [status, setStatus] = useState<DisplayStatus | "">("");
  const [groupId, setGroupId] = useState("");
  const [audioOnly, setAudioOnly] = useState(false);
  const [search, setSearch] = useState("");
  const [form, setForm] = useState<{ edit?: DisplayItem } | null>(null);
  const [secret, setSecret] = useState<DisplaySecretResponse | null>(null);

  const reloadAll = () => {
    reload();
    reloadGroups();
  };
  const groupName = new Map((groups ?? []).map((g) => [g.id, g.name]));
  const nodeName = new Map((nodes ?? []).map((n) => [n.id, n.name]));
  const takenNodes = new Map((displays ?? []).filter((d) => d.nodeId).map((d) => [d.nodeId!, d.id]));
  const namedNodes = (nodes ?? []).map((n) => ({ id: n.id, name: n.name }));

  const count = (s: DisplayStatus) => (displays ?? []).filter((d) => d.status === s).length;
  const withBattery = (displays ?? []).filter((d) => d.battery !== null);
  const batteryCount = (l: DisplayItem["battery"]) => withBattery.filter((d) => d.battery === l).length;

  const filtered = useMemo(() => {
    if (!displays) return [];
    return displays
      .filter((d) => !status || d.status === status)
      .filter((d) => !groupId || d.groupId === groupId)
      .filter((d) => !audioOnly || d.audio !== null)
      .filter((d) => !search || d.name.toLowerCase().includes(search.toLowerCase()) || d.id.toLowerCase().includes(search.toLowerCase()))
      .sort(byBatteryFirst);
  }, [displays, status, groupId, audioOnly, search]);

  const columns: Column<DisplayItem>[] = [
    { key: "id", label: "Устройство", render: (d) => <span className="mono">{d.id}</span>, sortValue: (d) => d.id },
    { key: "name", label: "Имя", render: (d) => d.name, sortValue: (d) => d.name },
    { key: "status", label: "Связь", render: (d) => <Badge tone={STATUS_TONE[d.status]}>{STATUS_LABEL[d.status]}</Badge>, sortValue: (d) => d.status },
    { key: "battery", label: "Батарея", render: (d) => <BatteryGauge d={d} />, sortValue: (d) => d.batteryPct ?? -1 },
    { key: "location", label: "Локация", render: (d) => (d.groupId && groupName.get(d.groupId)) || "—", sortValue: (d) => (d.groupId && groupName.get(d.groupId)) || "" },
    { key: "node", label: "Узел", render: (d) => (d.nodeId && nodeName.get(d.nodeId)) || "—", sortValue: (d) => (d.nodeId && nodeName.get(d.nodeId)) || "" },
    { key: "audio", label: "Звук", render: (d) => (d.audio ? "♪" : "—"), sortValue: (d) => (d.audio ? 1 : 0) },
  ];

  const device = deviceId ? (displays ?? []).find((d) => d.id === deviceId) : undefined;

  return (
    <div className="screen-grid">
      <p className="hint-text master-intro">
        Все физические точки (ESP32 + e-paper + звук) списком, без привязки к локации или узлу — состояние и полный набор команд.
        Локация (фон площадки) и узел (что показывает точка в мире) — на своих экранах, «Локации» и «Узлы».
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
          key={form.edit?.id ?? "new"}
          editing={form.edit}
          groups={groups ?? []}
          nodes={namedNodes}
          takenNodes={takenNodes}
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
      {device && (
        <Panel title={`Устройство «${device.name}»`} action={<AppButton onClick={() => navigate("devices")}>закрыть</AppButton>}>
          <DeviceDetail
            display={device}
            groups={groups ?? []}
            channels={channels ?? []}
            nodes={namedNodes}
            takenNodes={takenNodes}
            onChanged={reloadAll}
            onEdit={() => setForm({ edit: device })}
            onSecret={(r) => {
              setSecret(r);
              reload();
            }}
          />
        </Panel>
      )}
      <Panel
        title={`Устройства${displays ? ` (${filtered.length}${filtered.length !== displays.length ? ` из ${displays.length}` : ""})` : ""}`}
        action={
          <span className="filter-row filter-wrap">
            <AppInput value={search} onChange={(e) => setSearch(e.target.value)} placeholder="поиск по имени/id" aria-label="поиск устройств" />
            <AppSelect value={status} onChange={(e) => setStatus(e.target.value as DisplayStatus | "")} aria-label="фильтр по связи">
              {STATUS_FILTERS.map((s) => (
                <option key={s.value} value={s.value}>
                  {s.label}
                </option>
              ))}
            </AppSelect>
            <AppSelect value={groupId} onChange={(e) => setGroupId(e.target.value)} aria-label="фильтр по локации">
              <option value="">любая локация</option>
              {(groups ?? []).map((g) => (
                <option key={g.id} value={g.id}>
                  {g.name}
                </option>
              ))}
            </AppSelect>
            <label className="sound-check">
              <input type="checkbox" checked={audioOnly} onChange={(e) => setAudioOnly(e.target.checked)} /> только со звуком
            </label>
            <AppButton variant="primary" onClick={() => setForm({})}>
              + устройство
            </AppButton>
          </span>
        }
      >
        <AsyncPanel data={displays} error={error} isEmpty={() => filtered.length === 0} emptyLabel="устройств пока нет — добавьте первое">
          {() => <DataTable columns={columns} rows={filtered} rowKey={(d) => d.id} onRowClick={(d) => navigate("devices", d.id)} />}
        </AsyncPanel>
      </Panel>
    </div>
  );
}
