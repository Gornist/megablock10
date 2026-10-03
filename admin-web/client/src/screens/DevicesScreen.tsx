import { useMemo, useState } from "react";
import type { DisplayItem, DisplayStatus } from "../api/types";
import { AsyncPanel } from "../design/AsyncPanel";
import { AppButton, AppInput, AppSelect, Panel } from "../design/components";
import { DataTable, type Column } from "../design/DataTable";
import { navigate } from "../router";
import { BatteryGauge } from "./displays/BatteryGauge";
import { DeviceDetail } from "./displays/DeviceDetail";
import { DeviceStats } from "./displays/DeviceStats";
import { StatusBadge } from "./displays/DeviceStatus";
import { byBatteryFirst, STATUS_LABEL } from "./displays/displayUtil";
import { useDeviceData } from "./displays/useDeviceData";
import { useDeviceEditor } from "./displays/useDeviceEditor";

const STATUS_FILTERS: { value: DisplayStatus | ""; label: string }[] = [
  { value: "", label: "любая связь" },
  ...(Object.entries(STATUS_LABEL) as [DisplayStatus, string][]).map(([value, label]) => ({ value, label })),
];

/**
 * Устройства — плоский список всех физических точек (ESP32 + e-paper + звук), без привязки к локации или узлу: раньше
 * полное состояние и управление были только внутри «Локаций» (разворот строки), а в карточке узла — урезанная копия.
 * Здесь — один список «вот мои N коробок, вот их состояние», строка ведёт в ту же каноничную карточку (`DeviceDetail`),
 * что и на «Локациях»/«Узлах».
 */
export function DevicesScreen({ deviceId }: { deviceId?: string }) {
  const data = useDeviceData();
  const { displays, error, groups, nodeName } = data;
  const editor = useDeviceEditor(data);
  const [status, setStatus] = useState<DisplayStatus | "">("");
  const [groupId, setGroupId] = useState("");
  const [audioOnly, setAudioOnly] = useState(false);
  const [search, setSearch] = useState("");

  const groupName = new Map(groups.map((g) => [g.id, g.name]));

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
    { key: "status", label: "Связь", render: (d) => <StatusBadge status={d.status} />, sortValue: (d) => d.status },
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
      <DeviceStats displays={displays ?? []} />
      {editor.secretPanel}
      {editor.formPanel}
      {device && (
        <Panel title={`Устройство «${device.name}»`} action={<AppButton onClick={() => navigate("devices")}>закрыть</AppButton>}>
          <DeviceDetail display={device} {...editor.detailProps(device)} />
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
              {groups.map((g) => (
                <option key={g.id} value={g.id}>
                  {g.name}
                </option>
              ))}
            </AppSelect>
            <label className="sound-check">
              <input type="checkbox" checked={audioOnly} onChange={(e) => setAudioOnly(e.target.checked)} /> только со звуком
            </label>
            <AppButton variant="primary" onClick={() => editor.openNew()}>
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
