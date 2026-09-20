import { createContext, useContext, useState, type ReactNode } from "react";
import { type Session, api, clearSession, loadSession, saveSession } from "../api/client";

interface AuthContextValue {
  session: Session | null;
  setSession: (s: Session) => void;
  logout: () => void;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSessionState] = useState<Session | null>(() => loadSession());

  const setSession = (s: Session) => {
    saveSession(s);
    setSessionState(s);
  };
  const logout = () => {
    // Сначала закрываем сессию на сервере (заголовок собирается синхронно, до очистки), потом стираем локальную копию.
    // Ответ не ждём: даже если сеть моргнула, мастер всё равно выходит из интерфейса.
    api.post("/api/auth/logout").catch(() => {});
    clearSession();
    setSessionState(null);
  };

  return <AuthContext.Provider value={{ session, setSession, logout }}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth вне AuthProvider");
  return ctx;
}
