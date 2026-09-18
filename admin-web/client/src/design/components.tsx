import type { ReactNode } from "react";
import "./components.css";

export function Panel({ title, action, children, className }: { title?: ReactNode; action?: ReactNode; children: ReactNode; className?: string }) {
  return (
    <section className={`panel ${className ?? ""}`}>
      {(title || action) && (
        <header className="panel-header">
          {title && <h3>{title}</h3>}
          {action}
        </header>
      )}
      <div className="panel-body">{children}</div>
    </section>
  );
}

export function StatTile({ label, value, tone }: { label: string; value: ReactNode; tone?: "ok" | "danger" | "accent" }) {
  return (
    <div className={`stat-tile ${tone ?? ""}`}>
      <div className="stat-tile-value mono">{value}</div>
      <div className="stat-tile-label status-caps">{label}</div>
    </div>
  );
}

export function Badge({ children, tone }: { children: ReactNode; tone?: "ok" | "danger" | "accent" | "neutral" }) {
  return <span className={`badge status-caps ${tone ?? "neutral"}`}>{children}</span>;
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
    <button type={type} className={`app-button ${variant}`} onClick={onClick} disabled={disabled}>
      {children}
    </button>
  );
}

export function AppInput(props: React.InputHTMLAttributes<HTMLInputElement>) {
  return <input {...props} className={`app-input ${props.className ?? ""}`} />;
}

export function AppSelect({ children, ...props }: React.SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <select {...props} className={`app-select ${props.className ?? ""}`}>
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
      <div className="dialog-panel" onClick={(e) => e.stopPropagation()}>
        <h3>{title}</h3>
        {body && <p className="hint-text dialog-body">{body}</p>}
        {children}
        <div className="dialog-actions">
          <AppButton onClick={onCancel}>отмена</AppButton>
          <AppButton variant={confirmVariant} onClick={onConfirm} disabled={confirmDisabled}>
            {confirmText}
          </AppButton>
        </div>
      </div>
    </div>
  );
}
