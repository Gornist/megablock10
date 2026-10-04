import type { CSSProperties, ReactNode } from "react";

interface AttnRowProps {
  /** Цвет полоски слева: crit — срочно, warn — внимание, info — к сведению. */
  severity: "crit" | "warn" | "info";
  title: ReactNode;
  /** Бейдж и подобное между заголовком и описанием (в строке запроса к Сети). */
  afterTitle?: ReactNode;
  detail: ReactNode;
  /** Доп. класс описания (например hint-text — приглушённый текст). */
  detailClassName?: string;
  /** Тег описания: span по умолчанию, div — если внутри несколько строк. */
  detailAs?: "span" | "div";
  detailStyle?: CSSProperties;
  /** Строка кликабельна (подчёркивание заголовка по наведению); сам обработчик — onClick. */
  clickable?: boolean;
  onClick?: () => void;
  style?: CSSProperties;
  /** Всё, что справа от описания: время, бейджи, кнопки; и любые строки после основной. */
  children?: ReactNode;
}

/** Строка-тревога (.attn-item): заголовок, описание и хвост действий. Общая для обзора («Требует внимания») и панелей «Сети». */
export function AttnRow({ severity, title, afterTitle, detail, detailClassName, detailAs: Detail = "span", detailStyle, clickable, onClick, style, children }: AttnRowProps) {
  return (
    <div className={`attn-item sev-${severity}${clickable ? " clickable" : ""}`} style={style} onClick={onClick}>
      <span className="attn-title">{title}</span>
      {afterTitle}
      <Detail className={detailClassName ? `attn-detail ${detailClassName}` : "attn-detail"} style={detailStyle}>
        {detail}
      </Detail>
      {children}
    </div>
  );
}
