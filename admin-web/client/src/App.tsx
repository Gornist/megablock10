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
import { SoundScreen } from "./screens/SoundScreen";
import { useEffect } from "react";
import { useHashRoute, navigate } from "./router";
import { NAV, resolveSection } from "./nav";
import { AppButton } from "./design/components";

function Shell() {
  const { session, logout } = useAuth();
  const route = useHashRoute();

  const section = resolveSection(route[0]);
  // Прежний адрес (#displays, #sound) — заменить в истории на новый, чтобы «назад» не возвращал на редирект.
  useEffect(() => {
    if (route[0] && section !== route[0]) window.location.replace(`#/${[section, ...route.slice(1)].map(encodeURIComponent).join("/")}`);
  }, [route, section]);

  if (!session) return <LoginScreen />;

  return (
    <div className="app-shell">
      <aside className="app-sidebar">
        <h1>
          <span>
            МЕГАБЛОК №10
            <span className="app-sidebar-sub status-caps">коллектор</span>
          </span>
        </h1>
        {/* Срочное объявление — в одно нажатие с любого экрана. */}
        <button className={`sidebar-announce status-caps${section === "announce" ? " active" : ""}`} onClick={() => navigate("announce")}>
          📢 громкая связь
        </button>
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
        {/* До разбора по экранам (шаги 3–5 перекомпоновки): точки и группы — прежний экран дисплеев, звук — прежний экран. */}
        {section === "locations" && <DisplaysScreen />}
        {(section === "announce" || section === "channels") && <SoundScreen />}
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
