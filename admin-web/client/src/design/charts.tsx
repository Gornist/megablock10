import { formatNumber } from "../format";

/**
 * Графики без библиотеки — несколько десятков строк SVG вместо десятков килобайт
 * бандла (дашборд раздаётся с одной машины по игровому Wi-Fi, лишний вес заметен).
 */

export function LineChart({ points, height = 140, format = formatNumber }: { points: { t: number; v: number }[]; height?: number; format?: (v: number) => string }) {
  if (points.length < 2) return <div className="empty-state status-caps">мало данных для графика</div>;
  const W = 600;
  const pad = 6;
  const minT = points[0].t;
  const maxT = points[points.length - 1].t;
  const vs = points.map((p) => p.v);
  const minV = Math.min(0, ...vs);
  const maxV = Math.max(...vs, minV + 1);
  const x = (t: number) => pad + ((t - minT) / Math.max(1, maxT - minT)) * (W - 2 * pad);
  const y = (v: number) => height - pad - ((v - minV) / (maxV - minV)) * (height - 2 * pad);
  const line = points.map((p, i) => `${i === 0 ? "M" : "L"}${x(p.t).toFixed(1)},${y(p.v).toFixed(1)}`).join(" ");
  const area = `${line} L${x(maxT).toFixed(1)},${height - pad} L${x(minT).toFixed(1)},${height - pad} Z`;
  const time = (t: number) => new Date(t).toLocaleTimeString("ru-RU", { hour: "2-digit", minute: "2-digit" });

  return (
    <div className="chart">
      <svg viewBox={`0 0 ${W} ${height}`} preserveAspectRatio="none" role="img" aria-label="график">
        <path d={area} className="chart-area" />
        <path d={line} className="chart-line" fill="none" />
      </svg>
      <div className="chart-axis mono">
        <span>{time(minT)}</span>
        <span>
          {format(minV)} … {format(maxV)}
        </span>
        <span>{time(maxT)}</span>
      </div>
    </div>
  );
}

const STACK = [
  { key: "success", label: "успех", color: "var(--ok)" },
  { key: "partial", label: "частично", color: "var(--warn)" },
  { key: "fail", label: "провал", color: "var(--bad)" },
] as const;

/** Столбики по часам, поделённые на исходы взлома. */
export function OutcomeBars({ buckets, height = 110 }: { buckets: { t: number; success: number; partial: number; fail: number }[]; height?: number }) {
  const totals = buckets.map((b) => b.success + b.partial + b.fail);
  const max = Math.max(1, ...totals);
  const W = 600;
  const bw = W / buckets.length;
  return (
    <div className="chart">
      <svg viewBox={`0 0 ${W} ${height}`} preserveAspectRatio="none" role="img" aria-label="взломы по часам">
        {buckets.map((b, i) => {
          let yTop = height;
          return STACK.map((s) => {
            const h = (b[s.key] / max) * (height - 4);
            yTop -= h;
            return h > 0 ? <rect key={`${i}-${s.key}`} x={i * bw + 1} y={yTop} width={Math.max(1, bw - 2)} height={h} fill={s.color} /> : null;
          });
        })}
      </svg>
      <div className="chart-axis mono">
        <span>{new Date(buckets[0].t).toLocaleTimeString("ru-RU", { hour: "2-digit", minute: "2-digit" })}</span>
        <span>
          {STACK.map((s) => (
            <span key={s.key} className="chart-legend" style={{ color: s.color }}>
              ■ {s.label}{" "}
            </span>
          ))}
          · макс. {max}/ч
        </span>
        <span>сейчас</span>
      </div>
    </div>
  );
}

/** Горизонтальный «бар» доли: для источников эмиссии и рейтингов. */
export function ShareBar({ value, max, tone = "accent" }: { value: number; max: number; tone?: "accent" | "danger" | "ok" }) {
  const pct = max > 0 ? Math.min(100, (Math.abs(value) / max) * 100) : 0;
  return (
    <span className="share-bar">
      <span className={`share-bar-fill ${value < 0 ? "danger" : tone}`} style={{ width: `${pct}%` }} />
    </span>
  );
}
