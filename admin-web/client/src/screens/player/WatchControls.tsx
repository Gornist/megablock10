import { useState } from "react";
import { useWatch } from "../../api/useWatch";
import { AppButton, AppInput } from "../../design/components";

/** «Следить» за игроком с пометкой — общий для всех мастеров список наблюдения. */
export function WatchControls({ publicKeyB64 }: { publicKeyB64: string }) {
  const watch = useWatch();
  const watched = watch.byKey.get(publicKeyB64);
  const [note, setNote] = useState("");
  return (
    <>
      <AppButton variant={watched ? "primary" : "default"} onClick={() => (watched ? void watch.remove(publicKeyB64) : void watch.set(publicKeyB64, note))}>
        {watched ? "★ под наблюдением" : "☆ следить"}
      </AppButton>
      {watched ? (
        <AppInput
          placeholder="пометка (Enter — сохранить)"
          defaultValue={watched.note}
          key={watched.note}
          onKeyDown={(e) => {
            if (e.key === "Enter") void watch.set(publicKeyB64, e.currentTarget.value);
          }}
        />
      ) : (
        <AppInput placeholder="пометка для наблюдения" value={note} onChange={(e) => setNote(e.target.value)} />
      )}
    </>
  );
}
