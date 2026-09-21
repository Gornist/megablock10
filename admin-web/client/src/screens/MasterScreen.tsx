import { useState } from "react";
import { AppButton } from "../design/components";
import { ContainerForm } from "./master/ContainerForm";
import { MastersTab } from "./master/MastersTab";
import { ProvisionForm } from "./master/ProvisionForm";
import { RamForm } from "./master/RamForm";
import { ShardForm } from "./master/ShardForm";

const SUB_TABS = ["Персонаж", "Контейнер", "Шард", "RAM", "Мастера"] as const;

export function MasterScreen() {
  const [tab, setTab] = useState<(typeof SUB_TABS)[number]>("Персонаж");
  return (
    <div className="screen-grid">
      <p className="hint-text master-intro">
        Генерирует QR персонажей (первый запуск одним кодом), контейнеров, шардов и RAM-апгрейдов — печатайте или показывайте с экрана заранее, до игры. То же шифрование и тот же формат,
        что раньше был только в Мастерской на телефоне — игрок сканирует как обычно, разницы не видно.
      </p>
      <div className="filter-row">
        {SUB_TABS.map((t) => (
          <AppButton key={t} variant={t === tab ? "primary" : "default"} onClick={() => setTab(t)}>
            {t}
          </AppButton>
        ))}
      </div>
      {tab === "Персонаж" && <ProvisionForm />}
      {tab === "Контейнер" && <ContainerForm />}
      {tab === "Шард" && <ShardForm />}
      {tab === "RAM" && <RamForm />}
      {tab === "Мастера" && <MastersTab />}
    </div>
  );
}
