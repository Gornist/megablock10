import { useMemo, useState } from "react";

export interface Column<T> {
  key: string;
  label: string;
  render: (row: T) => React.ReactNode;
  sortValue?: (row: T) => string | number;
}

export function DataTable<T>({ columns, rows, onRowClick, rowKey }: {
  columns: Column<T>[];
  rows: T[];
  onRowClick?: (row: T) => void;
  rowKey: (row: T) => string;
}) {
  const [sortKey, setSortKey] = useState<string | null>(null);
  const [asc, setAsc] = useState(true);

  const sorted = useMemo(() => {
    if (!sortKey) return rows;
    const col = columns.find((c) => c.key === sortKey);
    if (!col?.sortValue) return rows;
    const copy = [...rows];
    copy.sort((a, b) => {
      const av = col.sortValue!(a);
      const bv = col.sortValue!(b);
      const cmp = av < bv ? -1 : av > bv ? 1 : 0;
      return asc ? cmp : -cmp;
    });
    return copy;
  }, [rows, sortKey, asc, columns]);

  function onHeaderClick(col: Column<T>) {
    if (!col.sortValue) return;
    if (sortKey === col.key) setAsc(!asc);
    else {
      setSortKey(col.key);
      setAsc(true);
    }
  }

  return (
    <table className="data-table">
      <thead>
        <tr>
          {columns.map((c) => (
            <th key={c.key} onClick={() => onHeaderClick(c)}>
              {c.label}
              {sortKey === c.key ? (asc ? " ▲" : " ▼") : ""}
            </th>
          ))}
        </tr>
      </thead>
      <tbody>
        {sorted.map((row) => (
          <tr key={rowKey(row)} onClick={() => onRowClick?.(row)}>
            {columns.map((c) => (
              <td key={c.key}>{c.render(row)}</td>
            ))}
          </tr>
        ))}
      </tbody>
    </table>
  );
}
