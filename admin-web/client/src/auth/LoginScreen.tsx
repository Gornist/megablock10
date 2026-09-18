import { useState } from "react";
import { api, ApiError } from "../api/client";
import { AppButton, AppInput, Field, Panel } from "../design/components";
import { useAuth } from "./AuthContext";

export function LoginScreen() {
  const { setSession } = useAuth();
  const [name, setName] = useState("");
  const [token, setToken] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const result = await api.post<{ sessionToken: string; master: { id: string; name: string }; expiresAt: number }>(
        "/api/auth/login",
        { name, token },
      );
      setSession(result);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : "не удалось связаться с сервером");
    } finally {
      setBusy(false);
    }
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
