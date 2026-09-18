import { useState } from "react";
import { api } from "../api/client";
import { useAsyncAction } from "../api/useAsyncAction";
import { AppButton, AppInput, Field, Panel } from "../design/components";
import { useAuth } from "./AuthContext";

export function LoginScreen() {
  const { setSession } = useAuth();
  const [name, setName] = useState("");
  const [token, setToken] = useState("");
  const { busy, error, run } = useAsyncAction({ fallbackError: "не удалось связаться с сервером" });

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    const res = await run(() =>
      api.post<{ sessionToken: string; master: { id: string; name: string }; expiresAt: number }>("/api/auth/login", { name, token }),
    );
    if (res.ok) setSession(res.value);
  }

  return (
    <div className="login-screen">
      <Panel title="Вход мастера" className="login-panel">
        <form onSubmit={submit} className="login-form">
          <Field label="Имя">
            <AppInput value={name} onChange={(e) => setName(e.target.value)} autoFocus />
          </Field>
          <Field label="Токен">
            <AppInput type="password" value={token} onChange={(e) => setToken(e.target.value)} />
          </Field>
          {error && <div className="login-error">{error}</div>}
          <AppButton type="submit" variant="primary" disabled={busy || !name || !token}>
            {busy ? "Проверка…" : "Войти"}
          </AppButton>
        </form>
      </Panel>
    </div>
  );
}
