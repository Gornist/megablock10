import { useCallback, useEffect, useRef, useState } from "react";

/** Объявление — секунды; минута — с запасом, дальше запись останавливается сама. */
export const MAX_RECORD_SECONDS = 60;

export type RecorderState = "idle" | "recording";

/**
 * Запись с микрофона ноутбука/телефона мастера (MediaRecorder). Микрофон браузер даёт только в защищённом контексте
 * (https или localhost): по голому http из локальной сети кнопка записи недоступна — остаётся «из файла».
 */
export function useRecorder(onRecorded: (data: ArrayBuffer) => void) {
  const [state, setState] = useState<RecorderState>("idle");
  const [seconds, setSeconds] = useState(0);
  const [error, setError] = useState<string | null>(null);
  const rec = useRef<{ recorder: MediaRecorder; stream: MediaStream; timer: number } | null>(null);
  const available = typeof window !== "undefined" && window.isSecureContext && !!navigator.mediaDevices?.getUserMedia && typeof MediaRecorder !== "undefined";

  const cleanup = useCallback(() => {
    const r = rec.current;
    if (!r) return;
    window.clearInterval(r.timer);
    r.stream.getTracks().forEach((t) => t.stop());
    rec.current = null;
  }, []);

  const stop = useCallback(() => {
    const r = rec.current;
    if (r && r.recorder.state !== "inactive") r.recorder.stop();
  }, []);

  const start = useCallback(async () => {
    setError(null);
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true } });
      const recorder = new MediaRecorder(stream);
      const chunks: Blob[] = [];
      recorder.ondataavailable = (e) => e.data.size > 0 && chunks.push(e.data);
      recorder.onstop = async () => {
        cleanup();
        setState("idle");
        const blob = new Blob(chunks, { type: recorder.mimeType });
        if (blob.size > 0) onRecorded(await blob.arrayBuffer());
      };
      const startedAt = Date.now();
      const timer = window.setInterval(() => {
        const s = Math.floor((Date.now() - startedAt) / 1000);
        setSeconds(s);
        if (s >= MAX_RECORD_SECONDS) stop();
      }, 250);
      rec.current = { recorder, stream, timer };
      setSeconds(0);
      recorder.start();
      setState("recording");
    } catch (e) {
      cleanup();
      setError(e instanceof DOMException && e.name === "NotAllowedError" ? "браузер не дал доступ к микрофону" : "не удалось включить микрофон");
    }
  }, [cleanup, onRecorded, stop]);

  useEffect(() => cleanup, [cleanup]);

  return { available, state, seconds, error, start, stop };
}
