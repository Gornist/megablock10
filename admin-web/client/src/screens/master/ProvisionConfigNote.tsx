import type { ProvisionsResponse } from "../../api/types";

/** Что нужно знать мастеру про содержимое QR: адрес и код игры подставляются сервером, вводить их руками не нужно. */
export function ProvisionConfigNote({ config }: { config: ProvisionsResponse["config"] }) {
  return (
    <p className="hint-text">
      В QR подставляются: адрес сервера{" "}
      {config.url ? <span className="mono">{config.url}</span> : <b>не определён (задайте PUBLIC_URL на сервере — иначе останется адрес из сборки)</b>} и код игры{" "}
      {config.secretSet ? "(включён)" : "(на сервере не задан)"}. Код игры лежит в QR: не выкладывайте снимки и лишние распечатки.
    </p>
  );
}
