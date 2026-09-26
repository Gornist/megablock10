import type { ReactNode } from "react";
import "./components.css";

/*
 * Три формы среза augmented-ui — те же, что в гайдлайне телефона (раздел 4): std (правый верхний +
 * левый нижний) для кнопок и панелей-карточек, tab (только правый нижний) для плиток/меток/полей/строк,
 * dlg (только правый верхний) для модальных окон. Размер и цвет среза — CSS-переменные
 * --aug-tr/--aug-bl/--aug-br/--aug-border-bg на самом элементе (components.css).
 */
const AUG_STD = "tr-clip bl-clip border";
const AUG_TAB = "br-clip border";
const AUG_DLG = "tr-clip border";

export function Panel({ title, action, children, className }: { title?: ReactNode; action?: ReactNode; children: ReactNode; className?: string }) {
  return (
    <section className={`panel ${className ?? ""}`} data-augmented-ui={AUG_STD}>
      {(title || action) && (
        <header className="panel-header">
          {title && <h3>{title}</h3>}
          {action}
        </header>
      )}
      {/* Панель вкладывает кнопки/поля/бейджи с другой формой среза (tab) — сброс обязателен, иначе
          augmented-ui унаследовала бы срез родителя на вложенных элементах. */}
      <div className="panel-body" data-augmented-ui-reset="">
        {children}
      </div>
    </section>
  );
}

export function StatTile({ label, value, tone }: { label: string; value: ReactNode; tone?: "ok" | "danger" | "money" | "accent" }) {
  return (
    <div className={`stat-tile ${tone ?? ""}`} data-augmented-ui={AUG_TAB}>
      <div className="stat-tile-value mono">{value}</div>
      <div className="stat-tile-label status-caps">{label}</div>
    </div>
  );
}

export function Badge({ children, tone }: { children: ReactNode; tone?: "ok" | "danger" | "warn" | "accent" | "info" | "neutral" }) {
  return (
    <span className={`badge status-caps ${tone ?? "neutral"}`} data-augmented-ui={AUG_TAB}>
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
    <button type={type} className={`app-button ${variant}`} onClick={onClick} disabled={disabled} data-augmented-ui={AUG_STD}>
      {children}
    </button>
  );
}

/** Поля ввода — форма tab (только br), как в гайдлайне: тёмный текстовый контейнер, а не рамка-акцент. */
const AUG_FIELD = AUG_TAB;

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
      <div className="dialog-panel" onClick={(e) => e.stopPropagation()} data-augmented-ui={AUG_DLG}>
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
