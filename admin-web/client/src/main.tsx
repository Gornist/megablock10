import { StrictMode } from "react";
import { createRoot } from "react-dom/client";

// Интерфейс — только кириллица и латиница, поэтому берём конкретные
// файлы подгрупп (latin/cyrillic), а не зонтичные *.css — те тянут ещё и
// greek/vietnamese/cyrillic-ext и т.д., которые здесь никогда не используются.
import "@fontsource/jura/latin-500.css";
import "@fontsource/jura/latin-600.css";
import "@fontsource/jura/cyrillic-500.css";
import "@fontsource/jura/cyrillic-600.css";
import "@fontsource/jetbrains-mono/latin-400.css";
import "@fontsource/jetbrains-mono/latin-500.css";
import "@fontsource/jetbrains-mono/cyrillic-400.css";
import "@fontsource/jetbrains-mono/cyrillic-500.css";
import "@fontsource/ibm-plex-sans/latin-400.css";
import "@fontsource/ibm-plex-sans/latin-500.css";
import "@fontsource/ibm-plex-sans/cyrillic-400.css";
import "@fontsource/ibm-plex-sans/cyrillic-500.css";

import "./design/tokens.css";
import "./design/layout.css";
import App from "./App";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
