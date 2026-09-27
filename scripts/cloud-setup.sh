#!/bin/bash
# Скрипт настройки облачного окружения Claude Code (claude.ai/code) для MegaBlock10.
# Копия того, что вставлено в настройки окружения (меню окружения в заголовке сессии → Edit → Setup script):
# правите здесь — вставьте туда заново. Самодостаточный (не читает репозиторий) и идемпотентный: повторный запуск ничего не ломает.
# Что даёт сессии: Android SDK 34 для :app, зеркало Maven Central для Gradle и Robolectric, UTF-8 в выводе Gradle,
# kotlin-language-server для плагина KotlinSense, PlatformIO с платформой ESP32 и wokwi-cli для прошивки QR-дисплея
# (firmware/display, docs/firmware-plan.md).
#
# Сеть окружения (Network access) — кроме доступного по умолчанию, должны быть разрешены:
#   api.registry.platformio.org, dl.registry.platformio.org — PlatformIO: платформа ESP32, тулчейн, библиотеки;
#   wokwi.com — симулятор Wokwi (wokwi-cli подключается к wss://wokwi.com/api/ws/beta).
# Токен Wokwi — не сюда: переменная окружения WOKWI_CLI_TOKEN в настройках окружения (и секрет с тем же именем в GitHub Actions).
set -euo pipefail

SDK=${ANDROID_HOME:-/root/android-sdk}
MIRROR=https://maven-central.storage-download.googleapis.com/maven2/

# 1. Android SDK: cmdline-tools → platform 34, build-tools 34.0.0, platform-tools (compileSdk/targetSdk = 34 в app/build.gradle.kts).
if [ ! -x "$SDK/cmdline-tools/latest/bin/sdkmanager" ]; then
  mkdir -p "$SDK/cmdline-tools"
  tmp=$(mktemp -d)
  curl -fsSL https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -o "$tmp/ct.zip"
  unzip -q "$tmp/ct.zip" -d "$tmp"
  rm -rf "$SDK/cmdline-tools/latest"; mv "$tmp/cmdline-tools" "$SDK/cmdline-tools/latest"; rm -rf "$tmp"
fi
if [ ! -d "$SDK/platforms/android-34" ] || [ ! -d "$SDK/build-tools/34.0.0" ] || [ ! -x "$SDK/platform-tools/adb" ]; then
  yes | "$SDK/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$SDK" --licenses > /dev/null || true
  "$SDK/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$SDK" "platforms;android-34" "build-tools;34.0.0" "platform-tools" > /dev/null
fi

# 2. Gradle: repo.maven.apache.org → зеркало (прямой Maven Central из облака режется по частоте запросов).
#    Robolectric качает android-all во время теста сам, мимо репозиториев Gradle: без зеркала repo1.maven.org отвечает 429
#    и первый прогон тестов в новой сессии красный (2 теста LootSlotOrderTest, 25.09).
mkdir -p ~/.gradle/init.d
cat > ~/.gradle/init.d/maven-central-mirror.gradle <<EOF
def mirror = '$MIRROR'
settingsEvaluated { s ->
  [s.pluginManagement.repositories, s.dependencyResolutionManagement.repositories].each { repos ->
    repos.withType(MavenArtifactRepository).configureEach { r ->
      if (r.url.toString().startsWith('https://repo.maven.apache.org')) r.url = mirror
    }
  }
}
// Robolectric качает android-all во время теста сам, мимо репозиториев Gradle; repo1.maven.org отвечает 429.
allprojects {
  tasks.withType(Test).configureEach { systemProperty 'robolectric.dependency.repo.url', mirror }
}
EOF

# 3. Переменные для shell сессии: SDK для Gradle и UTF-8 — клиент Gradle кодирует вывод по локали, при пустом LANG русский — «???».
#    Блок — в НАЧАЛО ~/.bashrc: штатный .bashrc выходит на `[ -z "$PS1" ] && return`, а shell агента неинтерактивный —
#    дописанное в конец не выполнялось (25.09: LANG в сессии пустой, хотя блок в файле был).
touch ~/.bashrc
if ! grep -q 'MB10: окружение' ~/.bashrc; then
  tmp=$(mktemp)
  cat > "$tmp" <<EOF
# MB10: окружение (scripts/cloud-setup.sh)
export ANDROID_HOME=$SDK
export ANDROID_SDK_ROOT=$SDK
export LANG=C.UTF-8
export PATH="\$HOME/.local/bin:\$PATH"
EOF
  cat ~/.bashrc >> "$tmp"; mv "$tmp" ~/.bashrc
fi

# 4. kotlin-language-server для плагина KotlinSense (.claude/settings.json; его .lsp.json зовёт kotlin-language-server из PATH).
KLS_VERSION=1.3.13
if [ ! -x "$HOME/.kotlin-language-server/bin/kotlin-language-server" ]; then
  tmp=$(mktemp -d)
  curl -fsSL "https://github.com/fwcd/kotlin-language-server/releases/download/$KLS_VERSION/server.zip" -o "$tmp/server.zip"
  unzip -q "$tmp/server.zip" -d "$tmp"
  rm -rf "$HOME/.kotlin-language-server"; mv "$tmp/server" "$HOME/.kotlin-language-server"; rm -rf "$tmp"
fi
mkdir -p "$HOME/.local/bin"
ln -sf "$HOME/.kotlin-language-server/bin/kotlin-language-server" "$HOME/.local/bin/kotlin-language-server"

# 5. Плагины Claude Code. enabledPlugins из .claude/settings.json облачная сессия при старте не ставит (25.09:
#    installed_plugins.json пуст, маркетплейс KotlinSense даже не добавлен) — ставим сами, в пользовательскую область.
#    Ошибка здесь не должна валить настройку: без плагинов сессия работает.
CLAUDE_BIN=$(command -v claude || echo /opt/claude-code/bin/claude)
if [ -x "$CLAUDE_BIN" ]; then
  "$CLAUDE_BIN" plugin marketplace add anthropics/claude-plugins-official || true
  "$CLAUDE_BIN" plugin marketplace add SUDARSHANCHAUDHARI/KotlinSense || true
  "$CLAUDE_BIN" plugin install code-review@claude-plugins-official || true
  "$CLAUDE_BIN" plugin install kotlinsense@kotlinsense || true
fi

# 6. Прошивка QR-дисплея (firmware/display). Сборка и тесты ядра на ПК — CMake + g++ (есть в образе); плата — PlatformIO;
#    эмулятор — wokwi-cli. Без доступа к реестру PlatformIO или к wokwi.com настройка не падает: остальное окружение работает.
if ! command -v pio > /dev/null; then
  pip3 install -q platformio 2> /dev/null || pip3 install -q --break-system-packages platformio || true
fi
if command -v pio > /dev/null; then
  pio settings set enable_telemetry No > /dev/null || true   # иначе стучится в collector.platformio.org
  # Платформа, фреймворк, тулчейн ESP32-S3 и библиотеки — заранее (≈1 ГБ, первая сборка в сессии иначе ждёт минуты).
  # Те же версии, что в firmware/display/platformio.ini; скрипт самодостаточный, поэтому проект — временный.
  tmp=$(mktemp -d)
  printf '%s\n' '[env:crowpanel579]' 'platform = espressif32@^6.9.0' 'framework = arduino' 'board = esp32-s3-devkitc-1' \
    'lib_deps =' '  zinggjm/GxEPD2@^1.6.0' '  adafruit/Adafruit GFX Library@^1.11.9' '  adafruit/Adafruit BusIO@^1.16.1' \
    '  bblanchon/ArduinoJson@^7.2.0' > "$tmp/platformio.ini"
  (cd "$tmp" && pio pkg install > /dev/null 2>&1) ||
    echo "PlatformIO: реестр недоступен (api/dl.registry.platformio.org в Network access?) — сборка для платы только в CI"
  rm -rf "$tmp"
fi
WOKWI_VERSION=v0.27.1
if [ ! -x "$HOME/.local/bin/wokwi-cli" ]; then
  mkdir -p "$HOME/.local/bin"
  curl -fsSL "https://github.com/wokwi/wokwi-cli/releases/download/$WOKWI_VERSION/wokwi-cli-linuxstatic-x64" -o "$HOME/.local/bin/wokwi-cli" &&
    chmod +x "$HOME/.local/bin/wokwi-cli" || echo "wokwi-cli не скачан"
fi

echo "MB10 cloud setup: SDK $(ls "$SDK/platforms" | tr '\n' ' '), kotlin-language-server $KLS_VERSION, init.d, ~/.bashrc, плагины, $(command -v pio > /dev/null && echo "PlatformIO, ")wokwi-cli $WOKWI_VERSION готовы"
