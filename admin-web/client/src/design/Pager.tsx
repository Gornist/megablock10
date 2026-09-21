import { AppButton } from "./components";

/** Переключатель страниц под длинными списками (журнал, события, история игрока): раньше один и тот же блок был скопирован в три экрана. */
export function Pager({
  page,
  pageSize,
  total,
  onPage,
  prevLabel = "← назад",
  nextLabel = "вперёд →",
}: {
  page: number;
  pageSize: number;
  total: number;
  onPage: (page: number) => void;
  prevLabel?: string;
  nextLabel?: string;
}) {
  return (
    <div className="pager">
      <AppButton onClick={() => onPage(Math.max(0, page - 1))} disabled={page === 0}>
        {prevLabel}
      </AppButton>
      <span className="mono">стр. {page + 1}</span>
      <AppButton onClick={() => onPage(page + 1)} disabled={(page + 1) * pageSize >= total}>
        {nextLabel}
      </AppButton>
    </div>
  );
}
