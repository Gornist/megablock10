import type { ReactNode } from "react";
import "./components.css";

/** Общий мискин augmented-ui для этого дашборда: два противоположных угла срезаны (фирменный силуэт), плюс рамка по контуру среза. Размер и цвет среза — CSS-переменные --aug-tl/--aug-br/--aug-border-bg на самом элементе (components.css). */
const AUG = "tl-clip br-clip border";

export function Panel({ title, action, children, className }: { title?: ReactNode; action?: ReactNode; children: ReactNode; className?: string }) {
  return (
    <section className={`panel ${className ?? ""}`} data-augmented-ui={AUG}>
      {(title || action) && (
        <header className="panel-header">
          {title && <h3>{title}</h3>}
          {action}
        </header>
      )}
      {/* Панель вкладывает кнопки/поля/бейджи с теми же позициями среза (tl+br) — по правилам augmented-ui
          это «граничный случай», сброс не обязателен, но панель — единственное место с вложенностью на
          несколько уровней, поэтому reset ставится явно, для устойчивости при будущих правках вёрстки. */}
      <div className="panel-body" data-augmented-ui-reset="">
        {children}
      </div>
    </section>
  );
}

export function StatTile({ label, value, tone }: { label: string; value: ReactNode; tone?: "ok" | "danger" | "accent" }) {
  return (
    <div className={`stat-tile ${tone ?? ""}`} data-augmented-ui={AUG}>
      <div className="stat-tile-value mono">{value}</div>
      <div className="stat-tile-label status-caps">{label}</div>
    </div>
  );
}

export function Badge({ children, tone }: { children: ReactNode; tone?: "ok" | "danger" | "accent" | "info" | "neutral" }) {
  return (
    <span className={`badge status-caps ${tone ?? "neutral"}`} data-augmented-ui={AUG}>
      {children}
    </span>
  );
}

export function AppButton({
  children,
  onClick,
  variant = "default",
  type = "button",
  disabled,
}: {
  children: ReactNode;
  onClick?: () => void;
  variant?: "default" | "primary" | "danger";
  type?: "button" | "submit";
  disabled?: boolean;
}) {
  return (
    <button type={type} className={`app-button ${variant}`} onClick={onClick} disabled={disabled} data-augmented-ui={AUG}>
      {children}
    </button>
  );
}

/** Поля ввода — только один срезанный угол (br), потемнее панелей и кнопок: это текстовый контейнер, а не рамка-акцент, полный tl+br съедал бы больше места под курсор и лево-выравненный текст. */
const AUG_FIELD = "br-clip border";

export function AppInput(props: React.InputHTMLAttributes<HTMLInputElement>) {
  return <input {...props} className={`app-input ${props.className ?? ""}`} data-augmented-ui={AUG_FIELD} />;
}

export function AppSelect({ children, ...props }: React.SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <select {...props} className={`app-select ${props.className ?? ""}`} data-augmented-ui={AUG_FIELD}>
      {children}
    </select>
  );
}

export function HexRow({ children }: { children: ReactNode }) {
  return (
    <div className="hex-row">
      <span className="hex-bullet" />
      <span className="hex-row-content mono">{children}</span>
    </div>
  );
}

export function EmptyState({ children }: { children: ReactNode }) {
  return <div className="empty-state status-caps">{children}</div>;
}

export function ErrorNote({ children }: { children: ReactNode }) {
  return <div className="login-error">Не удалось загрузить: {children}</div>;
}

/** Пара label+input, по образцу LabeledField в Android-Мастерской — раньше на клиенте этот блок вручную повторялся в каждой форме. */
export function Field({
  label,
  children,
}: {
  label: string;
  children: ReactNode;
}) {
  return (
    <>
      <label className="status-caps">{label}</label>
      {children}
    </>
  );
}

/**
 * Модальное подтверждение с опциональным текстовым полем — замена
 * window.prompt() в Реестре тиражей (нативный попап ломал фирменный HUD).
 * confirmDisabled — например, чтобы не дать подтвердить с пустым основанием.
 */
export function AppDialog({
  title,
  body,
  confirmText = "Подтвердить",
  confirmVariant = "primary",
  confirmDisabled,
  onConfirm,
  onCancel,
  children,
}: {
  title: string;
  body?: ReactNode;
  confirmText?: string;
  confirmVariant?: "primary" | "danger";
  confirmDisabled?: boolean;
  onConfirm: () => void;
  onCancel: () => void;
  children?: ReactNode;
}) {
  return (
    <div className="dialog-backdrop" onClick={onCancel}>
      <div className="dialog-panel" onClick={(e) => e.stopPropagation()} data-augmented-ui={AUG}>
        <h3>{title}</h3>
        {body && <p className="hint-text dialog-body">{body}</p>}
        {children}
        <div className="dialog-actions" data-augmented-ui-reset="">
          <AppButton onClick={onCancel}>отмена</AppButton>
          <AppButton variant={confirmVariant} onClick={onConfirm} disabled={confirmDisabled}>
            {confirmText}
          </AppButton>
        </div>
      </div>
    </div>
  );
}
