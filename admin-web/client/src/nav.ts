/**
 * Меню коллектора — по вопросу, с которым мастер приходит на экран (владелец: «узел-контейнер и есть QR-дисплей со звуком»):
 * «Игра» — игроки, деньги, арбитраж; «Мир» — узлы, что они показывают и что звучит, локации. Порядок внутри группы — по
 * частоте на игре.
 */
export const NAV: { title: string; items: { path: string; label: string }[] }[] = [
  {
    title: "Игра",
    items: [
      { path: "overview", label: "Обзор" },
      { path: "events", label: "События" },
      { path: "players", label: "Игроки" },
      { path: "factions", label: "Фракции" },
      { path: "economy", label: "Экономика" },
      { path: "transfers", label: "Переводы" },
      { path: "announcements", label: "Объявления" },
      { path: "audit", label: "Журнал" },
    ],
  },
  {
    title: "Мир",
    items: [
      { path: "nodes", label: "Узлы" },
      { path: "locations", label: "Локации" },
      { path: "announce", label: "Громкая связь" },
      { path: "channels", label: "Каналы звука" },
      { path: "master", label: "Мастерская" },
      { path: "slots", label: "Реестр тиражей" },
    ],
  },
];

/** Прежние адреса экранов, которых больше нет в меню, — закладки мастеров не должны вести в пустоту. */
export const REDIRECTS: Record<string, string> = {
  displays: "nodes",
  sound: "announce",
};

/** Куда на самом деле ведёт адрес: прежний — на новый экран, пустой — на Обзор. */
export function resolveSection(section: string | undefined): string {
  if (!section) return "overview";
  return REDIRECTS[section] ?? section;
}
