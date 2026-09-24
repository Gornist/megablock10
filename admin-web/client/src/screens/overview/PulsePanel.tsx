import type { Pulse, PulseSample } from "../../api/types";
import { useApiData } from "../../api/useApiData";
import { POLL_SLOW_MS } from "../../api/pollIntervals";
import { AsyncPanel } from "../../design/AsyncPanel";
import { LineChart } from "../../design/charts";
import { Panel } from "../../design/components";

const metrics: { title: string; value: (s: PulseSample) => number }[] = [
  { title: "На связи", value: (s) => s.online },
  { title: "Записей в минуту", value: (s) => s.records },
  { title: "Отклонено в минуту", value: (s) => s.rejected },
  { title: "Взломов в минуту", value: (s) => s.breaches },
];

/** «Пульс игры»: последний час по минутным сэмплам сервера (lib/pulse.ts). По нему же работают детекторы аномалий. */
export function PulsePanel() {
  const { data, error } = useApiData<Pulse>("/api/pulse?minutes=60", { pollMs: POLL_SLOW_MS });
  return (
    <Panel title="Пульс игры · последний час">
      <AsyncPanel data={data} error={error} isEmpty={(d) => d.samples.length < 2} emptyLabel="пульс копится — первые сэмплы появятся через минуту">
        {(d) => (
          <div className="pulse-grid">
            {metrics.map((m) => (
              <div key={m.title}>
                <div className="status-caps">{m.title}</div>
                <LineChart points={d.samples.map((s) => ({ t: s.t, v: m.value(s) }))} height={70} />
              </div>
            ))}
          </div>
        )}
      </AsyncPanel>
    </Panel>
  );
}
