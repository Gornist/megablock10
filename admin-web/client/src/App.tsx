import { AuthProvider, useAuth } from "./auth/AuthContext";
import { LoginScreen } from "./auth/LoginScreen";
import { OverviewScreen } from "./screens/OverviewScreen";
import { PlayersScreen } from "./screens/PlayersScreen";
import { PlayerDetailScreen } from "./screens/PlayerDetailScreen";
import { NodesScreen } from "./screens/NodesScreen";
import { SlotsScreen } from "./screens/SlotsScreen";
import { TransfersScreen } from "./screens/TransfersScreen";
import { MasterScreen } from "./screens/MasterScreen";
import { FactionsScreen } from "./screens/FactionsScreen";
import { EconomyScreen } from "./screens/EconomyScreen";
import { AnnouncementsScreen } from "./screens/AnnouncementsScreen";
import { AuditScreen } from "./screens/AuditScreen";
import { EventsScreen } from "./screens/EventsScreen";
import { useHashRoute, navigate } from "./router";
import { AppButton } from "./design/components";

const NAV: { path: string; label: string }[] = [
  { path: "overview", label: "Обзор" },
  { path: "events", label: "События" },
  { path: "players", label: "Игроки" },
  { path: "factions", label: "Фракции" },
  { path: "economy", label: "Экономика" },
  { path: "nodes", label: "Узлы" },
  { path: "slots", label: "Реестр тиражей" },
  { path: "transfers", label: "Переводы" },
  { path: "announcements", label: "Объявления" },
  { path: "audit", label: "Журнал" },
  { path: "master", label: "Мастерская" },
];

function Shell() {
  const { session, logout } = useAuth();
  const route = useHashRoute();

  if (!session) return <LoginScreen />;

  const section = route[0] ?? "overview";

  return (
    <div className="app-shell">
      <header className="app-header">
        <h1>МЕГАБЛОК №10 · КОЛЛЕКТОР</h1>
        <nav>
          {NAV.map((n) => {
            const active = section === n.path;
            return (
              <button
                key={n.path}
                className={`nav-item status-caps ${active ? "active" : ""}`}
                onClick={() => navigate(n.path)}
                // Срез и рамка — только у активного пункта, он же и есть указатель «вы здесь»;
                // остальные — просто подписи, без коробки, чтобы меню не читалось решёткой.
                {...(active ? { "data-augmented-ui": "tl-clip br-clip border" } : {})}
              >
                {n.label}
              </button>
            );
          })}
        </nav>
        <div className="app-header-right">
          <span className="mono">{session.master.name}</span>
          <AppButton onClick={logout}>выйти</AppButton>
        </div>
      </header>
      <main className="app-main">
        {section === "overview" && <OverviewScreen />}
        {section === "players" && route[1] && <PlayerDetailScreen publicKeyB64={route[1]} />}
        {section === "players" && !route[1] && <PlayersScreen />}
        {section === "events" && <EventsScreen key={route.join("/")} preset={{ type: route[1], value: route[2] }} />}
        {section === "factions" && <FactionsScreen />}
        {section === "economy" && <EconomyScreen />}
        {section === "nodes" && <NodesScreen nodeId={route[1]} />}
        {section === "slots" && <SlotsScreen />}
        {section === "transfers" && <TransfersScreen />}
        {section === "announcements" && <AnnouncementsScreen />}
        {section === "audit" && <AuditScreen />}
        {section === "master" && <MasterScreen />}
      </main>
    </div>
  );
}

export default function App() {
  return (
    <AuthProvider>
      <Shell />
    </AuthProvider>
  );
}
