import type { ReactNode } from "react";
import { EmptyState, ErrorNote } from "./components";

interface AsyncPanelProps<T> {
  /** null — данные ещё не пришли (загрузка или сеть недоступна). */
  data: T | null;
  error?: string | null;
  loadingLabel?: string;
  /** Список загружен, но пуст (например, после фильтра) — своя подпись вместо children. */
  isEmpty?: (data: T) => boolean;
  emptyLabel?: ReactNode;
  children: (data: T) => ReactNode;
}

/**
 * Общий 3-варианта пэттерн «error && ErrorNote / data===null ? загрузка… :
 * контент», раньше вручную скопированный в NodesScreen, SlotsScreen,
 * TransfersScreen, PlayersScreen и Мастерской. Ошибка при этом не занимает
 * место загрузки/пустого состояния — пусто, если рядом уже есть ErrorNote
 * (взято из PlayersScreen, было `{error ? "" : "загрузка…"}`).
 */
export function AsyncPanel<T>({ data, error, loadingLabel = "загрузка…", isEmpty, emptyLabel, children }: AsyncPanelProps<T>) {
  return (
    <>
      {error && <ErrorNote>{error}</ErrorNote>}
      {data === null ? (
        <EmptyState>{error ? "" : loadingLabel}</EmptyState>
      ) : isEmpty?.(data) ? (
        <EmptyState>{emptyLabel}</EmptyState>
      ) : (
        children(data)
      )}
    </>
  );
}
