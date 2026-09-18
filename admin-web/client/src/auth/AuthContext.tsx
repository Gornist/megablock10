import { createContext, useContext, useState, type ReactNode } from "react";
import { type Session, clearSession, loadSession, saveSession } from "../api/client";

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
