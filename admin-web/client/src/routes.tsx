import type { ReactNode } from "react";
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
import { AnnounceScreen } from "./screens/AnnounceScreen";
import { ChannelsScreen } from "./screens/ChannelsScreen";
import { LocationsScreen } from "./screens/LocationsScreen";

/**
 * Экран по адресу: section → что показать (route — весь путь, #/nodes/<id> и т. п.). Каждый пункт меню (nav.ts) должен
 * быть здесь — это проверяет nav.test.ts; прежние адреса (#displays, #sound) сюда не попадают, их переводит resolveSection.
 */
export const SCREENS: Record<string, (route: string[]) => ReactNode> = {
  overview: () => <OverviewScreen />,
  events: (route) => <EventsScreen key={route.join("/")} preset={{ type: route[1], value: route[2] }} />,
  players: (route) => (route[1] ? <PlayerDetailScreen publicKeyB64={route[1]} /> : <PlayersScreen />),
  factions: () => <FactionsScreen />,
  economy: () => <EconomyScreen />,
  transfers: () => <TransfersScreen />,
  announcements: () => <AnnouncementsScreen />,
  audit: () => <AuditScreen />,
  nodes: (route) => <NodesScreen nodeId={route[1]} />,
  locations: () => <LocationsScreen />,
  announce: () => <AnnounceScreen />,
  channels: () => <ChannelsScreen />,
  master: () => <MasterScreen />,
  slots: () => <SlotsScreen />,
};
