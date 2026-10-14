# Настройка машины разработки для netrun (Ubuntu 24.04 LTS Desktop)

Машина разработки собирает приложение, эмулятор и мир (Godot), запускает стенд e2e и сервер Моста. Конфигурация: i7-9700T, 16 ГБ оперативной памяти, GTX 1650, Ubuntu 24.04 LTS Desktop.

## До скрипта (вручную)

1. **BIOS: включите VT-x (Intel VMX)** — для KVM и эмулятора.
2. **Ubuntu 24.04 LTS Desktop минимальная установка** (без дополнительных приложений).
3. **Swap 8–16 ГБ** — для сборок и роботестов.
4. **Постоянный IP** (192.168.X.Y; DHCP с резервированием или статический) — для подключения по SSH из Claude Code.
5. **SSH-ключ с Mac** (если подключаетесь из Claude Code):
   ```bash
   # На Mac: скопируйте открытый ключ
   cat ~/.ssh/id_ed25519.pub
   
   # На машине разработки: добавьте в ~/.ssh/authorized_keys
   mkdir -p ~/.ssh
   echo "ваш_публичный_ключ_с_Mac" >> ~/.ssh/authorized_keys
   chmod 600 ~/.ssh/authorized_keys
   ```

## Запуск скрипта

```bash
bash scripts/devbox-setup.sh                    # все шаги
bash scripts/devbox-setup.sh --no-nvidia        # без драйвера NVIDIA
bash scripts/devbox-setup.sh --android-only     # только Android SDK и эмуляторы
```

Скрипт идемпотентный: повторный запуск ничего не ломает. Длительность: 30–50 минут (зависит от интернета).

## После скрипта

Добавьте в `~/.bashrc` или `~/.zshrc`:

```bash
export ANDROID_HOME=$HOME/android-sdk
export ANDROID_SDK_ROOT=$HOME/android-sdk
export JAVA_HOME=/usr/lib/jvm/temurin-21-jdk-amd64
export PATH=$HOME/.local/bin:$PATH
```

Новый вход и проверка:

```bash
source ~/.bashrc
id -nG | grep kvm                              # убедитесь в членстве в группе kvm
java -version                                  # должна быть 21
sdkmanager --list_installed | head -10         # должны быть android-35, build-tools-35.0.1
godot --version                                # должна быть Godot 4.7.2
```

## Подключение из Claude Code (по SSH)

1. **Узнайте IP машины разработки:**
   ```bash
   hostname -I
   ```

2. **В Claude Code:** Claude Code > Settings > SSH > New connection:
   - Host: `192.168.X.Y` (IP машины)
   - User: (ваш пользователь на машине, обычно первый, кто логинился)
   - Port: 22 (по умолчанию)
   - Key: (выберите приватный ключ Ed25519)

3. **Сессия откроется в `$HOME`, абсолютные пути работают как обычно.**

## Запуск стенда e2e на машине разработки

```bash
cd ~/megablock10
scripts/e2e/up.sh              # запуск эмуляторов, сервера, APK (~3 мин)
scripts/e2e/run-all.sh         # все сценарии (проверка логики)
scripts/e2e/down.sh            # остановка
```

На второй и следующие запуски используйте `--keep-data`:

```bash
scripts/e2e/up.sh --keep-data  # не сбрасывать БД сервера
```

Если эмулятор завис, перезагрузитесь:

```bash
scripts/e2e/down.sh
pkill -f emulator || true
scripts/e2e/up.sh
```

## Запуск сервера Моста и мира (Godot)

На машине разработки (локально, без эмуляторов):

### 1. Сервер Моста (Kotlin + :kit)

```bash
cd ~/megablock10
./gradlew :netrun-bridge:test :netrun-bridge:detekt  # проверка
java -jar netrun-bridge/build/libs/*.jar             # запуск сервера (если собран)
```

Или из Claude Code по SSH.

### 2. Сервер мира (Godot headless)

```bash
cd ~/megablock10/netrun
godot --headless -- --tokens=t1:alice,t2:bob --exit-after=300
```

### 3. Плоская отладочная сборка (локально, с окном)

```bash
cd ~/megablock10/netrun
godot -- --flat --host=127.0.0.1 --port=7777 --token=t1
```

Управление: T зажать и смотреть на пол — прицел телепорта, отпустить — переместиться (C — отмена); при зажатой T Q/E выбирают поворот при телепорте (±90°);
ПКМ + мышь — осмотр, R — центровка, F / левый клик — взять предмет, 1–9 — демон, X — выйти чисто, Esc 3 с — экстренный выход.
Ходьба WASD выключена, включается флагом `--walk`; плавный или рывковый поворот стиком — `--turn=smooth` или `--turn=snap` (по умолчанию стик мир не вращает).

`godot` в неинтерактивном ssh на PATH нет — сначала `. ~/netrun-env.sh`. Аргументы игры при запуске из редактора
(`editor/run/main_run_args`) пишутся с ведущим `-- `, иначе Godot игре их не передаёт.

### 4. Очки Pico 4 по USB

Очки подключены к devbox кабелем; `adb` — после `. ~/netrun-env.sh`. Подключено ещё что-то (телефон, эмулятор) — `export ANDROID_SERIAL=<serial очков>`
(иначе `more than one device`). Известные ограничения очков (расширение айтрекинга, граница, режим рук, подпись, адрес и токен — файл `netrun.cfg`) —
`netrun/README.md`, «Pico 4».

- **Сборка для очков** — в своей копии проекта (не в `~/wt-godot`): `android/build` из `android_source.zip` шаблонов 4.7.2,
  `godot --headless --path <копия> --export-debug "Client Pico 4 (Android)"` (Gradle запускает сам экспорт, ~1,5 мин).
  Адрес сервера мира и токен — файлом на очках: `netrun/tools/pico.sh provision --host=<LAN-адрес devbox> --token=t1` (после каждого
  `adb uninstall` заново, `install -r` файл сохраняет); запасной способ для сборки на ПК — `-- --host=… --token=…` в `command_line/extra_args`.
- **Цикл:** `adb uninstall` (если подпись другая), `adb install -r <apk>` — **смотреть вывод**: при отказе на очках остаётся старая сборка;
  `adb logcat -c`, `tools/pico.sh launch`, `adb logcat -d | grep -E " godot +:|Fatal signal|F DEBUG"`; журнал игры — `tools/pico.sh log`
  (`user://logs` — внутренняя память приложения, читается через `run-as`).
- **Настройка комфорта без пересборки:** клиент читает необязательный `user://comfort.cfg` (секция `[comfort]`: `turn_mode`,
  `turn_speed_deg_s`, `turn_vignette`, `turn_ramp_up_s`, `turn_ramp_down_s`, `teleport_range`, `teleport_cooldown`, `teleport_blink_s`;
  пределы и значения по умолчанию — `netrun/client/comfort_config.gd`, `shared/rig_math.gd`). `tools/pico.sh tune` без аргументов показывает
  файл на очках; `tune turn_speed_deg_s=45 teleport_range=3.5` правит его (остальные ключи сохраняются), перезапускает приложение и печатает
  строку `comfort` из журнала; `tune --reset` удаляет файл. Файл пишется через `run-as` (отладочная сборка). Дальность и перезарядка
  телепорта ограничены пределами сервера (6 м, 0,6 с). Адрес сервера и токен через этот файл не передаются.
- **Без человека:** экран держат `adb shell svc power stayon true` и `adb shell input keyevent KEYCODE_WAKEUP` перед запуском. Но если на
  очках не задана граница или спят контроллеры при включённом отслеживании рук, система открывает поверх приложения свой экран и ставит его
  на паузу — XR-проверку (трекинг, связь из VR) тогда делает только человек в очках.
- **Пресеты рендера и серии замеров** (рефактор Сети, G2): умолчания приняты и живут в коде (`RenderConfig`: msaa 2, foveation 0, layers behind;
  `AssetMaterials.KNOBS`: вид V10), поэтому `netrun.cfg` теперь нужен только для сравнений. `netrun/tools/pico_stand.sh <пресет> [ключ=значение ...]`
  пишет секции `[render]` и `[assets]` на очки (остальной файл не трогает; `--show`, `--reset`); пресеты: `base` (чистые умолчания), `bench`
  (`perf=on`, `bench=entry`), `cloud-props` (+ `cloud=1`), `cloud-vol`/`cloud-vol-budget`/`cloud-all`/`cloud-all-imp` (облако (Б), регулятор, импостор), `probe-sweep` (`cloud-props-2s` и ручка `cloud_two_sided` удалены 14.10: +5,5 мс, 66 fps). Ключи `RenderConfig.KEYS` идут
  в `[render]`, остальные — в `[assets]`. `netrun/tools/pico_series.sh "имя=пресет ключ=значение" ...` прогоняет варианты подряд (конфиг →
  перезапуск → итог `[bench]`/`[probe]` → PNG кадра при `perf=diag`) в `~/pico-series/<время>`; `PICO_SERVER_CMD` — команда сервера мира.
  Грабли без человека: очки на столе засыпают по датчику (`dumpsys power` → `Asleep`; `svc power stayon true` не всегда хватает; на Pico помогли
  `setprop pvr.factorytest.never.sleep 1` и `persist.pvr.sleep_by_static 0` — вернуть после серии); камеры в тёмной комнате дают системный диалог
  «Слишком темно» — `am start` отвечает «kept for the user», игра не стартует, серия честно прерывается; закрыть диалог должен человек.
- **Один путь к очкам (Д5, `docs/devbox.md` «Д5»; решение владельца 13.10 после 17:27):** серия, запись конфига и перезапуск игры идут только через
  `box.sh pico run|ready|start|fg` — в скриптах Сети нет своих wake/sleep/stayon/KEYCODE и нажатий в системных окнах. Запуск серии одной командой
  на devbox: `netrun/tools/pico_series.sh "имя=пресет ключ=значение" …` — сам зовёт `ctl.sh pico run Godot ${PICO_RUN_MIN:-20} [--port 7777]
  [--timeout $PICO_RUN_TIMEOUT] -- …`: бронь → разбудить → ready по ТРЕКИНГУ (свет, граница, контроллеры) → снимки и logcat прогона в
  `PICO_RUN_DIR` (туда же результаты серии) → погасить → снять бронь, вердикт последней строкой `pico run: …`. Коды run: команда rc | 20 не
  готово/вылезло окно («нужен человек» — строка в `~/box/attention.log`, дальше Pipeline) | 21 бронь чужая | 124 таймаут | 2 аргументы. Внутри
  серии между вариантами: идемпотентный `pico ready Godot` → `pico start Godot <пакет/активити>` («kept for the user» = НЕ ГОТОВО, строка
  `pico fg` в выводе) → итог `[bench]`; исходный `netrun.cfg` сохраняется на входе и возвращается в trap, игра останавливается. Без ~/box/repo
  (не devbox) — серия напрямую через `am start`, `PICO_READY_CMD` по желанию. Темно/нет трекинга = «physical»: ждёт света, повторять не нужно.
  `pico_stand.sh` перед записью конфига зовёт `check pico` (чужая бронь — отказ «кто и до когда»); `dev.sh shot` ставит запуск Godot в очередь
  `gpu` (`ctl.sh run gpu Godot --name shot`, ожидание `SHOT_QUEUE_WAIT`, 900 с), свой `flock /tmp/display.lock` остаётся внутри. Сервер стенда на
  свободном порту из пула 7800–7899: `scripts/box.sh up stand Godot -- <srv_p2.sh> {PORT}`. Подготовка очков на `pico.sh tune` — под бронью:
  `box.sh pico run Godot 5 -- netrun/tools/pico.sh tune …`. Пресет `cloud-props` после B3 ≡ `bench` (`cloud=1` — умолчание `AssetMaterials`), оставлен алиасом.
  Самотест — `netrun/tools/box_guard_selftest.sh` (подложные ctl.sh и adb, `PICO_SERIAL=NOSUCH`, `BOX_TEST=1`; очков и `~/box` не касается; 21 проверка):
  проверки броней и серии гонять только им, а не рабочими скриптами по ssh — 13.10 17:27 так разбудили очки.
- **Падение в нативном коде:** кадры `libgodot_android.so` в tombstone без имён (библиотека шаблона уже без символов). Функцию находит
  дизассемблер по адресу кадра: `$ANDROID_HOME/ndk/<версия>/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-objdump -d --start-address=…`
  по `<копия>/android/build/build/intermediates/merged_native_libs/…/arm64-v8a/libgodot_android.so` (BuildId в tombstone должен совпасть).
  Символы Godot публикует только для template_release и редактора.

## Godot AI: агент `godot-dev` и тесты Godot-части

Живой редактор Godot с плагином [Godot AI](https://github.com/hi-godot/godot-ai) (MCP, v4.2.3) на devbox, на реальном дисплее (GNOME `:0`,
GTX 1650). Через него агент `godot-dev` (`.claude/agents/godot-dev.md`) правит сцены и ноды, запускает игру, снимает кадры и читает журналы.

- **Рабочая копия:** git worktree `~/wt-godot`, ветка `agent/godot` (от `agent/netrun`). Принести на Mac: `git fetch devbox agent/godot`.
- **Редактор:** `scripts/devbox-godot-ai.sh setup` (один раз: worktree, плагин с проверкой sha256, импорт), затем `start|stop|status`;
  `autostart` — поднимать при входе nick. Плагин в репозиторий не кладём (`netrun/.gitignore`): `start` дописывает в `project.godot`
  плагин, автозагрузку `_mcp_game_helper` и `run/main_run_args`, `stop` снимает; от забытого `stop` страхует хук `pre-commit`
  (ставит `setup`, или `scripts/devbox-godot-ai.sh hook`): в коммит уходит `project.godot` без этих строк, рабочий файл он не трогает.
  Файл в репозитории приведён к формату, который пишет редактор Godot 4.7, поэтому открытие проекта дерево не пачкает; если
  `git status` показывает `netrun/project.godot` — настройки действительно меняли.
- **Автозапуск сеанса.** После входа nick в GNOME `~/.config/autostart/devbox-session.desktop` запускает
  `/home/nick/box/repo/scripts/devbox-session-start.sh` — скрипт из клона репозитория, а не ручную копию (клон обновляет `scripts/box.sh sync`;
  расхождение видно в `scripts/box.sh status`). Порядок этапов: incy (VPN) → Tailscale (перезапуск только если не Running) → adb (user-служба
  `box-adb`) → Blender (blender-mcp на 9876, до 3 попыток) → ожидание редактора Godot на порту 8000 → самопроверка. Итог — `~/box/boot.report`,
  подробный журнал — `~/.local/state/devbox-session.log`. Редактор Godot AI поднимает отдельный `godot-ai.desktop`
  (`scripts/devbox-godot-ai.sh autostart`, через 20 с после входа); автозапуск сеанса лишь ждёт порт 8000 до 90 с и пишет проблему в отчёт,
  если редактор не поднялся. Нужны: autoConnect в incy и sudo без пароля на перезапуск `tailscaled` (`/etc/sudoers.d/devbox-tailscale`).
- **Godot не должен убивать общий adb.** При выходе Godot (в том числе `--headless --import` из `gdunit.sh`, `dev.sh`, `live_run.sh`…) вызывает `adb kill-server`
  (настройка редактора `export/android/shutdown_adb_on_exit`, по умолчанию true) — 13.10 это пять раз оборвало Pico и телефоны всем сессиям. Защита двойная:
  скрипты `netrun/tools/*.sh` и `~/pico-cfg/build.sh` экспортируют `ANDROID_ADB_SERVER_PORT=5099` (Godot убивает пустой порт, а не общий сервер), а в
  `~/.config/godot/editor_settings-4.7.tres` стоит `export/android/shutdown_adb_on_exit = false` (поставила сессия Devbox; при смене версии Godot файл
  называется иначе — строку добавить снова). Счётчик убийств — в `scripts/box.sh status`.
- **Клиент (Claude Code на Mac):** `.mcp.json` запускает `ssh devbox … uvx godot-ai attach` (stdio-мост) — туннеля и токенов нет. Телеметрию
  плагина отключает `GODOT_AI_DISABLE_TELEMETRY=1`.
- **Тесты — gdUnit4, как в CI:** `ssh devbox 'cd ~/wt-godot && netrun/tools/gdunit.sh [res://tests/файл_test.gd]'` (весь набор — 403 теста,
  зелёный при открытом редакторе; долго — через `devjob start`). Встроенный `test_run` плагина не используем: он не знает gdUnit4.
- **Что не покрыто:** снимки кадра идут из плоской сборки, VR (OpenXR, трекинг, кадр на Pico 4) на devbox не проверить.
- **Ловушки:** не искать редактор через `pkill -f`/`ps | grep` по строке из самой ssh-команды (убьёте сессию); после остановки ждать
  освобождения портов 8000/9500, lock в `~/.config/godot-ai/capabilities` не удалять — иначе «server start blocked».

## Диагностика

### Эмулятор не стартует

```bash
# Список запущенных
adb devices

# Принудительный перезапуск
adb -s emulator-5554 shell reboot
# или
emulator -avd Medium_Phone_API_35 -wipe-data &
```

### Нет интернета в эмуляторе (нормально)

Эмулятор подключен только к локальной сети (Wi-Fi 10.0.0.0/8). Интернет здесь не нужен.

### Java / gradle версия

```bash
java -version                    # должна быть 21
./gradlew --version              # Gradle 8.14+
```

### Память и диск

```bash
free -h                          # оперативная память (нужно ≥ 4 ГБ свободных)
df -h $HOME                      # диск (нужно ≥ 10 ГБ свободных для SDK и Godot)
```

## Файлы и пути

| Что | Где |
|---|---|
| Android SDK | `$ANDROID_HOME` (по умолчанию `$HOME/android-sdk`) |
| JDK 17 | `/usr/lib/jvm/temurin-17-jdk-amd64/bin/java` |
| JDK 21 | `/usr/lib/jvm/temurin-21-jdk-amd64/bin/java` (по умолчанию `JAVA_HOME`) |
| Godot 4.7.2 | `$HOME/.local/godot/godot-4.7.2-stable` (симлинк `~/.local/bin/godot`) |
| Шаблоны Godot | `$HOME/.local/share/godot/export_templates/4.7.2.stable/` |
| AVD эмуляторов | `$HOME/.android/avd/` (Medium_Phone_API_35.avd, Second_API_35.avd) |
| Логи эмулятора | `$HOME/.android/avd/Medium_Phone_API_35.avd/` (файлы logs в конфиге) |
| Репозиторий | `$HOME/megablock10` (по умолчанию, если установлено) |

## Стенд e2e на devbox (E1)

Полный `scripts/e2e/run-all.sh` на devbox зелёный (образ android-35, менять на 34 не пришлось). Две причины прежних красных сценариев были в стенде, не в приложении:

- **Локаль POSIX** (ssh без `LANG`): `grep -i` в `screen_has` не сворачивает регистр кириллицы, а заголовки рисуются заглавными, поэтому «Сообщение от мастера» (announcement, а за ним zz-provisioning) «не находилось» при том, что окно было на экране. `lib.sh` сам выставляет `LC_ALL=C.UTF-8`, если локаль не UTF-8.
- **Виртуальный Wi-Fi без интернета**: Android навсегда отключал сохранённую сеть `AndroidWifi` (`NETWORK_SELECTION_DISABLED_NO_INTERNET_PERMANENT`), `wlan0` оставался `NO-CARRIER`, в журнале `nets=[cell:IV]`, «привязано к Wi-Fi» не появлялось (wifi-bind, sec-alert, slot-race). `up.sh` выключает проверку (`settings put global captive_portal_mode 0`).

## Учения: выдернули питание

Проверка, что внезапное отключение питания площадки (мини-ПК с Мостом и сервером мира) ничего не теряет. Скрипт `netrun/tools/power_cut.sh` поднимает Мост (SQLite в WAL) и сервер мира, запускает ботов, ждёт, пока хотя бы две сессии откроются посреди забега, и убивает **всё разом** `kill -9` (Мост тоже), затем поднимает заново на той же базе и сверяет слепки до и после:

- число и набор id предметов те же, что в начальных данных (не пропал и не раздвоился), аудитор Моста без тревог;
- документы узлов на месте, версии не откатились, локдаун и цель мастера (`node_cfg.goal`) не изменились;
- открытых сессий нет: недоигранные закрыты сервером мира по окну возврата, остальные доиграны ботами второй волны.

Запуск на devbox (после `. ~/netrun-env.sh`): `timeout 900 netrun/tools/power_cut.sh`; на занятой машине — `BRIDGE_PORT=7610 LINE_PORT=7611 ENET_PORT=7977 …`. Итог — одна строка `POWER_CUT PASS|FAIL: …`, журналы и слепки (`before.json`, `after.json`) — в каталоге из последней строки. Что переживает рестарт сервера мира, лежит в документах Моста: локдаун и цели — `node`/`node_cfg`, шарды — предметы с владельцем `node:<узел>`, тревога и сроки пополнения слотов — `node.data.world` (`alert`, `alert_at`, `refill`).

### На машине площадки

1. Установить юниты из `netrun/tools/systemd/` (`netrun-bridge.service`, `netrun-world.service`, `netrun.target`) в `/etc/systemd/system/`, поправить пути и пользователя, положить ключи ролей в `/etc/netrun/keys.env` (права 600), `systemctl daemon-reload && systemctl enable --now netrun.target`.
2. Убедиться, что оба юнита активны: `systemctl is-active netrun-bridge netrun-world`.
3. Начать забеги (боты `soak.sh` или очки), затем выдернуть шнур питания (или `sudo systemctl kill -s KILL netrun-world netrun-bridge` для проверки без шнура: `Restart=always` поднимет оба за несколько секунд).
4. После загрузки: `systemctl is-active …` снова `active`, аудитор Моста без тревог, на дашборде число предметов то же, активные забеги продолжаются или закрыты как `emergency`.
