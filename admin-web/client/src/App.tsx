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
import { DisplaysScreen } from "./screens/DisplaysScreen";
import { useHashRoute, navigate } from "./router";
import { AppButton } from "./design/components";

/**
 * Меню слева, пункты — смысловыми группами: двенадцать подписей столбиком без групп читаются хуже, чем строка сверху.
 * Порядок внутри группы — по частоте на игре.
 */
const NAV: { title: string; items: { path: string; label: string }[] }[] = [
  {
    title: "Игра",
    items: [
      { path: "overview", label: "Обзор" },
      { path: "events", label: "События" },
      { path: "players", label: "Игроки" },
      { path: "factions", label: "Фракции" },
      { path: "economy", label: "Экономика" },
    ],
  },
  {
    title: "Мир",
    items: [
      { path: "nodes", label: "Узлы" },
      { path: "slots", label: "Реестр тиражей" },
      { path: "transfers", label: "Переводы" },
    ],
  },
  {
    title: "Мастер",
    items: [
      { path: "announcements", label: "Объявления" },
      { path: "master", label: "Мастерская" },
      { path: "audit", label: "Журнал" },
    ],
  },
  {
    title: "Площадка",
    items: [{ path: "displays", label: "Дисплеи" }],
  },
];

function Shell() {
  const { session, logout } = useAuth();
  const route = useHashRoute();

  if (!session) return <LoginScreen />;

  const section = route[0] ?? "overview";

  return (
    <div className="app-shell">
      <aside className="app-sidebar">
        <h1>
          <span>
            МЕГАБЛОК №10
            <span className="app-sidebar-sub status-caps">коллектор</span>
          </span>
        </h1>
        <nav aria-label="разделы">
          {NAV.map((g) => (
            <div key={g.title} className="nav-group">
              <div className="nav-group-title status-caps">{g.title}</div>
              {g.items.map((n) => {
                const active = section === n.path;
                return (
                  <button
                    key={n.path}
                    className={`nav-item status-caps ${active ? "active" : ""}`}
                    onClick={() => navigate(n.path)}
                    aria-current={active ? "page" : undefined}
                    // Срез и рамка — только у активного пункта, он же и есть указатель «вы здесь»;
                    // остальные — просто подписи, без коробки, чтобы меню не читалось решёткой.
                    {...(active ? { "data-augmented-ui": "br-clip border" } : {})}
                  >
                    {n.label}
                  </button>
                );
              })}
            </div>
          ))}
        </nav>
        <div className="app-sidebar-footer">
          <span className="mono">{session.master.name}</span>
          <AppButton onClick={logout}>выйти</AppButton>
        </div>
      </aside>
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
        {section === "displays" && <DisplaysScreen />}
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
