# Прошивка QR-дисплея (ESP32-S3 + e-paper)

Дисплей — «тупой» приёмник кадра: сервер мастера (`admin-web`) рисует QR и по TCP отдаёт 1-битный кадр, прошивка проверяет
его (длина, CRC, HMAC, версия), сохраняет во flash и показывает. Контракт — [docs/displays.md](../../docs/displays.md), план и
способ проверки без железа — [docs/firmware-plan.md](../../docs/firmware-plan.md).

```
lib/core/     ядро без Arduino: протокол, CRC32, SHA-256/HMAC, приём потока, сессия, устройство, Wi-Fi backoff; hal.h — интерфейсы платформы;
              звук: sound.* — плейлист, клип, объявление; mixer.* — микшер, IMA ADPCM, пересчёт частоты; json.*, wav.*
src/host/     та же прошивка программой для ПК: сокеты, каталог вместо flash, PNG вместо e-paper
src/esp32/    драйверы CrowPanel 5.79″: main.cpp — GxEPD2, Wi-Fi, lwIP, LittleFS, сторож, подсветка, кнопка, USB-консоль;
              audio.cpp — звук: microSD, MP3 (ESP8266Audio), задача звука, I²S;
              settings.cpp — настройки в NVS; selftest_task.cpp — самопроверка для Wokwi; board.h — общее
lib/selftest/ самопроверка — клиент протокола на BSD-сокетах (POSIX и lwIP): внутри платы в Wokwi и display_selftest на ПК
src/selftest/ display_selftest — та же самопроверка программой для ПК (против display_host или платы в сети)
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
`--hang-on-image N` (зависание в обновлении панели — срабатывает сторож, `--watchdog-ms`). Батарея: `--battery-pct N` — как с
топливомером, `--battery-mv N` — как с делителем, `--battery-drain P` — разряд P % в час (проверить остаток в коллекторе). REBOOT и сторож — повторный exec
самого себя: кадр и версия восстанавливаются из «flash», как на плате.

Звуковая точка (docs/sound-nodes.md): `--roles display,audio` — в HELLO роли и состояние звука, принимаются AUDIO_STATE, клипы,
объявления, LIST. Карта памяти — каталог `--sd dir` (по умолчанию `./fw-host/display-017-sd`): треки кладутся в `tracks/`, клипы
прошивка пишет в `clips/`; `--no-sd` — карты нет. Динамик — строки `AUDIO track … / volume … / clip …` в журнале; трек «звучит»
столько, сколько длился бы MP3 128 кбит/с этого размера (`--track-ms N` — одна длительность для всех). Сбой `--drop-mid-clip N` —
оборвать соединение после N-го куска клипа (проверка докачки). Состояние звука — во «flash» (`audio.bin`), фон после перезапуска
начинается до сети. Ядро звука — `lib/core/src/sound.*` (плейлист, клип, объявление), тесты — `test/core/sound_test.cpp`.

Проверка против настоящего сервера:

```bash
cd admin-web/server
npm run display-conformance -- --port 47217 --id display-017 --secret <hex>        # 20 сценариев C1–C20
FIRMWARE_HOST_BIN=$PWD/../../firmware/display/build/display_host npx tsx --test src/firmwareHost.test.ts   # сервер ↔ прошивка, сбои
FIRMWARE_HOST_BIN=$PWD/../../firmware/display/build/display_host npm run display-load   # 30 прошивок, лимит соединений, зависший
```

`display-load` (Ф6): групповая отправка на 1/5/10/30 дисплеев — время до DISPLAYED по каждому, одновременные соединения против
`DISPLAY_MAX_CONCURRENT`, «зависший» дисплей (SIGSTOP) не задерживает остальных; `--netem "delay 80ms 20ms loss 3%"` — плохая
сеть на lo (нужны sudo и модуль `sch_netem`: в CI есть, в облачной сессии Claude — нет). Таймауты — из `DISPLAY_*`, как у сервера.

Самопроверка (`ctest` гоняет её против `display_host`): `build/display_selftest --id … --secret … --port … [--reboot]` — 19 проверок
протокола (HELLO, IMAGE, BAD_CRC, чужой ключ, STALE, WRONG_DEVICE, неизвестный тип, BAD_MAGIC, таймауты, вытеснение, TEST,
BACKLIGHT) и перезагрузка с восстановлением кадра. Тот же код крутится внутри платы в Wokwi (ниже).

## Плата (CrowPanel 5.79″)

```bash
cd firmware/display
pio run -e crowpanel579 -t upload     # сборка и прошивка по USB
pio device monitor                    # журнал; сюда же — команды настройки
```

Первичная настройка — в USB-консоли одной строкой: JSON из коллектора («Локации» → «+ точка» → блок настроек; галочка «со звуком» добавляет роль audio) плюс Wi-Fi.

```
config {"id":"display-017","secret":"<64 hex>","port":47200,"width":272,"height":792,"wifiSsid":"<SSID>","wifiPassword":"<пароль>"}
```

Необязательно — статический адрес: `"ip"`, `"gateway"`, `"subnet"`, `"dns"` (иначе DHCP с резервом адреса на роутере); звуковая
точка — `"roles":["display","audio"]` (см. «Звук» ниже). Другие
команды: `status`, `reboot`, `clear-frame`. После настройки — `npm run display-conformance` против платы: те же C1–C20, что для
ПК (прогон оставляет на экране тестовый узор — потом отправьте QR заново).

Ориентация: дисплеи висят горизонтально, кадр 792×272 (по умолчанию в дашборде и в прошивке). Панель поворачивается по размеру
кадра из настроек: шире — горизонтально, выше — портрет; `MB10_PANEL_ROTATION=2` — если закреплена вверх ногами.

Выводы в `platformio.ini` сверены со схемой Elecrow (панель, питание панели, кнопка MENU). Измерения батареи на плате нет —
доработка: топливомер **MAX17048** (модуль по I²C: SDA → 8, SCL → 9, 3V3 и GND с гребёнки, вход батареи — «+» элементов
21700, не выход 5 В). Прошивка находит его при загрузке (`battery: MAX17048 version …` в журнале) и шлёт в HELLO заряд, % и
скорость; нет модуля — не шлёт. Делитель вместо топливомера — `MB10_BATTERY_ADC_PIN=8`, `MB10_I2C_SDA=-1`. Подсветка — наша
доработка, пока `-1`. USB-C идёт через CH340C на UART0, так что журнал — обычный `Serial` (`pio device
monitor`). Остальное железо платы (microSD, гребёнка 2×10, кнопки, светодиод) — [docs/sound-nodes.md](../../docs/sound-nodes.md).

## Звук (docs/sound-nodes.md)

Точка с ролью `audio` (в `config` — `"roles":["display","audio"]`) играет фон канала с microSD и объявления громкой связи.
Железо — слот microSD на CrowPanel (SPI: CS 10, MOSI 40, CLK 39, MISO 13, питание 42 — своя шина, не панели) и усилитель
**MAX98357A** на гребёнке: BCLK → 15, LRC → 16, DIN → 17, SD → 18 (прошивка держит его выключенным в тишине — без шипения),
VIN — от батареи/5 В, не от 3V3. Карта FAT32: треки — `/mb10/tracks/*.mp3` (заливаются руками, имена латиницей, MP3 44,1 кГц,
моно/стерео, 64–128 кбит/с), клипы объявлений прошивка сама пишет в `/mb10/clips`. Карту вставили/вынули — видно через 5–10 с,
в коллекторе «нет карты» / «нет на карте: N».

Задача звука — на ядре 1: MP3 → кольцевой буфер → микшер (фон × громкость с плавным переходом + сигнал + объявление, фон
на время объявления приглушается) → I²S 44,1 кГц; e-paper и сеть — на ядре 0, обновление панели звук не прерывает. Состояние
(канал, громкость, версия) — в LittleFS: после перезагрузки фон начинается до Wi-Fi. У звуковой точки Wi-Fi без сна модема.

## Эмулятор Wokwi (Ф4)

`crowpanel579-wokwi` — та же прошивка для ESP32-S3 в эмуляторе: вместо панели пишет в журнал `PANEL frame 792x272 crc=…`,
настройки вшиты (Wi-Fi `Wokwi-GUEST`, id `selftest-wokwi`, тестовый секрет), сторож — 5 с. Порт платы wokwi-cli наружу не
пробрасывает (`net.forward` есть только в расширении VS Code), поэтому сервер снаружи к ней не подключится — вместо этого
самопроверка (`lib/selftest`) крутится в своей задаче FreeRTOS и стучится в TCP-сервер этой же платы через `127.0.0.1`. Фазы
переживают перезагрузки в NVS: проверки протокола → REBOOT (причина `ESP_RST_SW`, кадр и версия из LittleFS) → зависание цикла →
сброс сторожем (`ESP_RST_TASK_WDT`; в Wokwi после паники часто последним пишется TG1WDT — `ESP_RST_INT_WDT`, тоже сторож; кадр
снова на месте) → `SELFTEST ALL PASSED`.

Звук в Wokwi: точка с ролью `audio`, I²S — заглушка (`MB10_AUDIO_STUB`: сэмплы выбрасываются, темп — по таймеру), microSD —
настоящая карта Wokwi (`diagram.json`, 8 МБ, пустая). Самопроверка кладёт на неё вшитый MP3 (`src/esp32/selftest_mp3.h`,
`tools/gen_selftest_mp3.py`) и проверяет: состояние звука и отказ старой версии, LIST, клип кусками с обрывом и докачкой,
объявление до «доиграло» в HELLO, декодирование MP3 с карты (треки сменяются), версию звука после REBOOT и сброса сторожем.

```bash
WOKWI_CLI_TOKEN=… firmware/display/tools/wokwi_selftest.sh     # сборка, склейка образа flash, wokwi-cli; журнал — wokwi-serial.log
```

Нужны PlatformIO, `wokwi-cli` (v0.27.1) и токен Wokwi в переменной окружения (в облачной сессии — `scripts/cloud-setup.sh` и
настройки окружения; в CI — секрет `WOKWI_CLI_TOKEN`, без него шаг пропускается с пометкой). Образ склеивается целиком
(загрузчик + таблица разделов + прошивка): с одним `firmware.bin` Wokwi кладёт свою таблицу разделов и LittleFS не там.

Первый же прогон нашёл баг, который на плате не дал бы загрузиться: сервер открывался раньше `WiFi.mode()`, стек lwIP не был
поднят — `assert … tcpip_send_msg_wait_sem (Invalid mbox)` и цикл перезагрузок.

## CI

`.github/workflows/firmware.yml`: тесты ядра, прошивка для ПК и самопроверка (и под ASan/UBSan), сервер мастера против прошивки
для ПК, нагрузка `display-load` (чистая сеть и netem), сборка для платы, самопроверка в Wokwi, артефакт `firmware.bin` и журнал
Wokwi.
