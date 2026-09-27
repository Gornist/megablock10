import type { DisplayPushPhase } from "../../api/types";
import { PUSH_STEPS, pushStep, type PushState } from "./displayUtil";

const MOCK_LABEL: Record<PushState | "draft", string> = {
  draft: "предпросмотр",
  sending: "передаётся",
  loaded: "загружено · обновляется",
  shown: "на экране",
  failed: "ошибка отправки",
  superseded: "заменён",
};

/**
 * Дисплей «как в руке»: корпус, e-paper с кадром в пропорциях панели (горизонтально, как висят, или портрет) (кадр ровно тот, что рисует сервер) и отметка состояния.
 * draft — ещё не отправлен; sending — картинка приглушена, по экрану бежит полоса передачи; loaded — e-paper «моргает», как при
 * полном обновлении; shown — чёткая; failed — приглушена, красная отметка.
 */
export function DisplayMock({
  png,
  width,
  height,
  state,
  caption,
  note,
}: {
  png: string | null;
  width: number;
  height: number;
  state: PushState | "draft";
  caption?: string;
  note?: string;
}) {
  return (
    <figure
      className={`display-mock display-mock-${state} display-mock-${width > height ? "landscape" : "portrait"}`}
      aria-label={`дисплей: ${MOCK_LABEL[state]}`}
    >
      <div className="display-mock-body">
        <div className="display-mock-screen" style={{ aspectRatio: `${width} / ${height}` }}>
          {png ? <img src={png} alt={state === "draft" ? "кадр для дисплея" : "кадр на дисплее"} /> : <span className="display-mock-empty">пусто</span>}
          {state === "sending" && <span className="display-mock-scan" />}
        </div>
        <span className="display-mock-led" />
      </div>
      <figcaption>
        <span className={`display-mock-tag display-mock-tag-${state}`}>{MOCK_LABEL[state]}</span>
        {caption && <span className="mono display-mock-caption">{caption}</span>}
        {note && <span className="hint-text">{note}</span>}
      </figcaption>
    </figure>
  );
}

/** Шкала «Подключение → Отправлено → Загружено → Отображено» по этапу отправки с сервера. */
export function PushSteps({ phase, failedAt }: { phase: DisplayPushPhase; failedAt?: DisplayPushPhase | null }) {
  const failed = phase === "FAILED";
  // Сорвалось — крестик на шаге, где оборвалась последняя попытка.
  const { done, current } = pushStep(failed ? (failedAt ?? "CONNECTING") : phase);
  return (
    <ol className="push-steps" aria-label="ход отправки">
      {PUSH_STEPS.map((label, i) => {
        const cls = i < done ? "done" : i === current ? (failed ? "failed" : phase === "RETRY" ? "retry" : "current") : "todo";
        return (
          <li key={label} className={`push-step push-step-${cls}`} aria-current={i === current ? "step" : undefined}>
            <span className="push-step-dot">{cls === "done" ? "✓" : cls === "failed" ? "✕" : i + 1}</span>
            {label}
          </li>
        );
      })}
    </ol>
  );
}
