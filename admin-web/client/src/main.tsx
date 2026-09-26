import { StrictMode } from "react";
import { createRoot } from "react-dom/client";

// Интерфейс — только кириллица и латиница, поэтому берём конкретные
// файлы подгрупп (latin/cyrillic), а не зонтичные *.css — те тянут ещё и
// greek/vietnamese/cyrillic-ext и т.д., которые здесь никогда не используются.
// Тот же набор весов, что у Android-приложения (ui-style-guide.md, раздел 3) —
// один шрифт на весь текст и заголовки (Fira), один на моно (Plex Mono).
import "@fontsource/fira-sans-condensed/latin-400.css";
import "@fontsource/fira-sans-condensed/latin-500.css";
import "@fontsource/fira-sans-condensed/latin-600.css";
import "@fontsource/fira-sans-condensed/cyrillic-400.css";
import "@fontsource/fira-sans-condensed/cyrillic-500.css";
import "@fontsource/fira-sans-condensed/cyrillic-600.css";
import "@fontsource/ibm-plex-mono/latin-400.css";
import "@fontsource/ibm-plex-mono/latin-500.css";
import "@fontsource/ibm-plex-mono/latin-600.css";
import "@fontsource/ibm-plex-mono/cyrillic-400.css";
import "@fontsource/ibm-plex-mono/cyrillic-500.css";
import "@fontsource/ibm-plex-mono/cyrillic-600.css";

import "./design/tokens.css";
import "./design/layout.css";
import App from "./App";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
