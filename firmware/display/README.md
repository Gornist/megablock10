# Прошивка QR-дисплея (ESP32-S3 + e-paper)

Дисплей — «тупой» приёмник кадра: сервер мастера (`admin-web`) рисует QR и по TCP отдаёт 1-битный кадр, прошивка проверяет
его (длина, CRC, HMAC, версия), сохраняет во flash и показывает. Контракт — [docs/displays.md](../../docs/displays.md), план и
способ проверки без железа — [docs/firmware-plan.md](../../docs/firmware-plan.md).

```
lib/core/     ядро без Arduino: протокол, CRC32, SHA-256/HMAC, приём потока, сессия, устройство, Wi-Fi backoff; hal.h — интерфейсы платформы
src/host/     та же прошивка программой для ПК: сокеты, каталог вместо flash, PNG вместо e-paper
src/esp32/    драйверы CrowPanel 5.79″: GxEPD2, Wi-Fi, lwIP, LittleFS, NVS, сторож, подсветка, кнопка, USB-консоль
test/core/    тесты ядра; test/vectors/protocol-v1.json — общие векторы с сервером (пишет admin-web: npm run display-vectors)
```

## Без платы (ПК)

Нужны CMake, g++ (или clang) и Python 3 — PlatformIO не нужен.

```bash
cmake -S firmware/display -B firmware/display/build && cmake --build firmware/display/build -j
ctest --test-dir firmware/display/build --output-on-failure          # тесты ядра

# прошивка как программа — прямая замена `npm run mock-display` (те же флаги)
firmware/display/build/display_host --id display-017 --secret <64 hex из дашборда> --port 47217 --delay 3000 --out ./fw-host
```

Кадр «панели» — `./fw-host/display-017.png`, «flash» — `./fw-host/display-017/frame.bin`. Сбои для проверки (снимаются при
«перезагрузке»): `--fail-display N` (панель не обновилась N раз), `--crash-on-save N` (процесс падает посреди N-й записи кадра),
`--hang-on-image N` (зависание в обновлении панели — срабатывает сторож, `--watchdog-ms`). REBOOT и сторож — повторный exec
самого себя: кадр и версия восстанавливаются из «flash», как на плате.

Проверка против настоящего сервера:

```bash
cd admin-web/server
npm run display-conformance -- --port 47217 --id display-017 --secret <hex>        # 20 сценариев C1–C20
FIRMWARE_HOST_BIN=$PWD/../../firmware/display/build/display_host npx tsx --test src/firmwareHost.test.ts   # сервер ↔ прошивка, сбои
```

## Плата (CrowPanel 5.79″)

```bash
cd firmware/display
pio run -e crowpanel579 -t upload     # сборка и прошивка по USB
pio device monitor                    # журнал; сюда же — команды настройки
```

Первичная настройка — в USB-консоли одной строкой: JSON из дашборда («Дисплеи» → «+ дисплей» → блок настроек) плюс Wi-Fi.

```
config {"id":"display-017","secret":"<64 hex>","port":47200,"width":272,"height":792,"wifiSsid":"<SSID>","wifiPassword":"<пароль>"}
```

Необязательно — статический адрес: `"ip"`, `"gateway"`, `"subnet"`, `"dns"` (иначе DHCP с резервом адреса на роутере). Другие
команды: `status`, `reboot`, `clear-frame`. После настройки — `npm run display-conformance` против платы: те же C1–C20, что для
ПК (прогон оставляет на экране тестовый узор — потом отправьте QR заново).

Выводы в `platformio.ini`: панель и кнопка — по примерам Elecrow для этой платы (сверить со схемой), подсветка и делитель
батареи — зависят от доработки платы, пока `-1` (выключено). Если журнал не виден в мониторе — плата может выводить `Serial` в
родной USB: добавить `-DARDUINO_USB_CDC_ON_BOOT=1`.

`crowpanel579-wokwi` — сборка для эмулятора Wokwi (Ф4): вместо панели пишет в журнал `PANEL frame 272x792 crc=…`.

## CI

`.github/workflows/firmware.yml`: тесты ядра (и под ASan/UBSan), сервер мастера против прошивки для ПК, сборка для платы и
артефакт `firmware.bin`.
