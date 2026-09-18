import { useEffect, useState } from "react";

/** Минимальный хэш-роутер — без библиотеки, чтобы не тащить лишнюю зависимость в бандл. */
export function useHashRoute(): string[] {
  const [hash, setHash] = useState(window.location.hash);
  useEffect(() => {
    const onChange = () => setHash(window.location.hash);
    window.addEventListener("hashchange", onChange);
    return () => window.removeEventListener("hashchange", onChange);
  }, []);
  const path = hash.replace(/^#\/?/, "");
  return path ? path.split("/").map(decodeURIComponent) : [];
}

export function navigate(...segments: string[]) {
  window.location.hash = "/" + segments.map(encodeURIComponent).join("/");
}
