---
paths:
  - "firmware/**"
  - "admin-web/server/src/displays/**"
  - "admin-web/server/src/audio/**"
  - "admin-web/server/src/routes/audio.ts"
  - ".github/workflows/firmware.yml"
---

# Прошивка и физические узлы (перенесено из CLAUDE.md 07.10 — грузится только при работе с этими путями)

| Что | Команда |
|---|---|
| Хост-тесты | `cmake -S firmware/display -B firmware/display/build && cmake --build … && ctest --test-dir …` |
| Плата | `pio run -e crowpanel579` |
| Wokwi | `firmware/display/tools/wokwi_selftest.sh` — квота CI-минут; в CI — только при правке кода платы |
| esp-emulator | `firmware/display/tools/espemu_selftest.sh` — без квоты (без SD/I²S) |

CI — `firmware.yml` (правка `firmware/`, `admin-web/server/src/displays/`, звука на сервере — `audio/`, `routes/audio.ts`); ≈5 мин.

Облачное окружение: `scripts/cloud-setup.sh` ставит PlatformIO с платформой ESP32 и `wokwi-cli`. В Network access окружения нужны
`api.registry.platformio.org`, `dl.registry.platformio.org`, `wokwi.com`; токен Wokwi — переменная окружения `WOKWI_CLI_TOKEN`
в настройках окружения и секрет с тем же именем в GitHub Actions, **не в репозитории и не в чате**.
