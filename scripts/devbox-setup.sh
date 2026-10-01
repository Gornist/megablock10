#!/bin/bash
# Скрипт настройки машины разработки на Ubuntu 24.04 LTS Desktop для проекта Мегаблок №10, netrun-d1.
# Идемпотентный: повторный запуск ничего не ломает.
# Используется на машине разработки с i7-9700T, 16 ГБ, GTX 1650; параметры подобраны для этой конфигурации.
#
# Установка:
#   bash scripts/devbox-setup.sh                    # все шаги
#   bash scripts/devbox-setup.sh --no-nvidia        # без драйвера NVIDIA
#   bash scripts/devbox-setup.sh --no-kvm           # без KVM/QEMU
#   bash scripts/devbox-setup.sh --android-only     # только Android SDK и эмуляторы
#
# Что даёт скрипт:
# - apt-пакеты: git, curl, unzip, build-essential, ssh-сервер, KVM и средства проверки (cpu-checker),
#   эмулятор QEMU, поддержка групп, Ruby и Python3;
# - JDK 17 и 21 (Temurin, совместимо со скриптами проекта);
# - Android SDK с command-line tools, platform-tools, build-tools 35.0.1, platforms android-35,
#   эмулятор и системный образ x86_64 API 35, создание AVD Medium_Phone_API_35 и Second_API_35;
# - Node.js 22 (как в CI/.github/workflows/main.yml);
# - Godot 4.7.2-stable Linux x86_64 и шаблоны экспорта 4.7.2;
# - Claude Code CLI;
# - локальный клон репозитория и local.properties для Gradle;
# - setup-hooks.sh для Git хуков.
#
# Требования: sudo (для установки системных пакетов и групп), интернет, ~30 ГБ дискового пространства.

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Флаги
NO_NVIDIA=0
NO_KVM=0
ANDROID_ONLY=0

# Разбор аргументов
while [[ $# -gt 0 ]]; do
  case $1 in
    --no-nvidia) NO_NVIDIA=1; shift ;;
    --no-kvm) NO_KVM=1; shift ;;
    --android-only) ANDROID_ONLY=1; NO_NVIDIA=1; NO_KVM=1; shift ;;
    *) echo "Неизвестный флаг: $1"; exit 1 ;;
  esac
done

echo -e "${GREEN}=== Начало настройки машины разработки ===${NC}"

# 1. Обновление apt
echo -e "${YELLOW}[1/10] Обновление пакетов...${NC}"
sudo apt-get update -qq || true
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq || true

# 2. Базовые пакеты
echo -e "${YELLOW}[2/10] Установка базовых пакетов (git, curl, unzip, build-essential, ssh, cpu-checker, qemu)...${NC}"
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  git curl unzip build-essential openssh-server cpu-checker qemu-system-x86-64 qemu-kvm \
  ruby python3 python3-pip ca-certificates 2>&1 | grep -v "^Get:\|^Hit:\|^Reading\|^Building" || true

# 3. Добавление текущего пользователя в группу kvm
echo -e "${YELLOW}[3/10] Добавление пользователя в группу kvm...${NC}"
if ! getent group kvm > /dev/null; then
  sudo groupadd kvm || true
fi
if ! id -nG "$(whoami)" | grep -qw kvm; then
  sudo usermod -aG kvm "$(whoami)"
  echo -e "${YELLOW}Пользователь добавлен в группу kvm. Изменение вступит в силу после перевхода.${NC}"
fi

# 4. Драйвер NVIDIA (опционально)
if [ "$NO_NVIDIA" -eq 0 ]; then
  echo -e "${YELLOW}[4/10] Установка драйвера NVIDIA...${NC}"
  sudo ubuntu-drivers install -y || echo -e "${RED}Драйвер NVIDIA не установлен (может быть видеокарта не NVIDIA)${NC}"
else
  echo -e "${YELLOW}[4/10] Пропуск установки драйвера NVIDIA (флаг --no-nvidia)${NC}"
fi

# 5. JDK 17 и 21 (Temurin)
echo -e "${YELLOW}[5/10] Установка JDK 17 и 21 (Temurin)...${NC}"
# Добавляем репозиторий Eclipse Temurin
if ! grep -q "adoptopenjdk\|eclipse" /etc/apt/sources.list.d/* 2>/dev/null; then
  curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public | sudo apt-key add - || true
  echo "deb https://packages.adoptium.net/artifactory/deb $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/adoptium.list > /dev/null || true
  sudo apt-get update -qq || true
fi

sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  temurin-17-jdk temurin-21-jdk 2>&1 | grep -v "^Get:\|^Hit:\|^Reading\|^Building" || true

# Установка JAVA_HOME как симлинки для совместимости со скриптами проекта
JAVA17_HOME=$(update-alternatives --list java 2>/dev/null | grep temurin-17 | head -1 | xargs dirname | xargs dirname)
JAVA21_HOME=$(update-alternatives --list java 2>/dev/null | grep temurin-21 | head -1 | xargs dirname | xargs dirname)

if [ -z "$JAVA17_HOME" ]; then
  JAVA17_HOME="/usr/lib/jvm/temurin-17-jdk-amd64"
fi
if [ -z "$JAVA21_HOME" ]; then
  JAVA21_HOME="/usr/lib/jvm/temurin-21-jdk-amd64"
fi

# 6. Android SDK
echo -e "${YELLOW}[6/10] Установка Android SDK...${NC}"
ANDROID_HOME="${ANDROID_HOME:-$HOME/android-sdk}"
mkdir -p "$ANDROID_HOME"

if [ ! -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]; then
  TMP_SDK=$(mktemp -d)
  echo "Скачивание Android command-line tools..."
  curl -fsSL "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip" \
    -o "$TMP_SDK/ct.zip" || { echo -e "${RED}Ошибка при скачивании SDK${NC}"; rm -rf "$TMP_SDK"; exit 1; }
  unzip -q "$TMP_SDK/ct.zip" -d "$TMP_SDK"
  rm -rf "$ANDROID_HOME/cmdline-tools/latest"
  mkdir -p "$ANDROID_HOME/cmdline-tools"
  mv "$TMP_SDK/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
  rm -rf "$TMP_SDK"
fi

if [ -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ]; then
  echo "Установка SDK packages..."
  yes | "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$ANDROID_HOME" \
    --licenses > /dev/null 2>&1 || true
  "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$ANDROID_HOME" \
    "platforms;android-35" "build-tools;35.0.1" "platform-tools" "emulator" \
    "system-images;android-35;google_apis;x86_64" > /dev/null 2>&1 || \
    echo -e "${RED}Ошибка при установке SDK packages${NC}"
fi

# 7. Создание AVD эмуляторов
echo -e "${YELLOW}[7/10] Создание AVD Medium_Phone_API_35 и Second_API_35...${NC}"
export ANDROID_AVD_HOME="$HOME/.android/avd"
mkdir -p "$ANDROID_AVD_HOME"

# Функция создания AVD
create_avd() {
  local avd_name=$1
  if [ ! -d "$ANDROID_AVD_HOME/$avd_name.avd" ]; then
    echo "Создание AVD $avd_name..."
    echo "no" | "$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager" create avd \
      -n "$avd_name" -k "system-images;android-35;google_apis;x86_64" \
      -d "pixel" 2>&1 | grep -v "^Error\|^WARNING" || true
  fi
}

create_avd "Medium_Phone_API_35"
create_avd "Second_API_35"

# 8. Node.js 22
echo -e "${YELLOW}[8/10] Установка Node.js 22...${NC}"
if ! command -v node > /dev/null || [ "$(node -v | cut -d. -f1 | sed 's/v//')" -lt 22 ]; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - || true
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nodejs 2>&1 | grep -v "^Get:\|^Hit:\|^Reading\|^Building" || true
fi

# 9. Godot 4.7.2-stable
echo -e "${YELLOW}[9/10] Установка Godot 4.7.2-stable и шаблонов экспорта...${NC}"
GODOT_VERSION="4.7.2"
GODOT_HOME="${GODOT_HOME:-$HOME/.local/godot}"
mkdir -p "$GODOT_HOME"

if [ ! -x "$GODOT_HOME/godot-$GODOT_VERSION-stable" ]; then
  TMP_GODOT=$(mktemp -d)
  echo "Скачивание Godot $GODOT_VERSION-stable..."
  curl -fsSL "https://github.com/godotengine/godot/releases/download/$GODOT_VERSION-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
    -o "$TMP_GODOT/godot.zip" || { echo -e "${RED}Ошибка при скачивании Godot${NC}"; rm -rf "$TMP_GODOT"; exit 1; }
  unzip -q "$TMP_GODOT/godot.zip" -d "$TMP_GODOT"
  mv "$TMP_GODOT/Godot_v${GODOT_VERSION}-stable_linux.x86_64" "$GODOT_HOME/godot-$GODOT_VERSION-stable"
  chmod +x "$GODOT_HOME/godot-$GODOT_VERSION-stable"
  rm -rf "$TMP_GODOT"
fi

# Шаблоны экспорта
GODOT_TEMPLATES_DIR="$HOME/.local/share/godot/export_templates/$GODOT_VERSION.stable"
mkdir -p "$GODOT_TEMPLATES_DIR"
if [ ! -f "$GODOT_TEMPLATES_DIR/export-templates.tpz" ]; then
  TMP_TEMPLATES=$(mktemp -d)
  echo "Скачивание шаблонов экспорта Godot..."
  curl -fsSL "https://github.com/godotengine/godot/releases/download/$GODOT_VERSION-stable/Godot_v${GODOT_VERSION}-stable_export_templates.tpz" \
    -o "$TMP_TEMPLATES/templates.tpz" || { echo -e "${RED}Ошибка при скачивании шаблонов${NC}"; rm -rf "$TMP_TEMPLATES"; exit 1; }
  unzip -q "$TMP_TEMPLATES/templates.tpz" -d "$GODOT_TEMPLATES_DIR" || true
  rm -rf "$TMP_TEMPLATES"
fi

# Создание симлинка в PATH
mkdir -p "$HOME/.local/bin"
ln -sf "$GODOT_HOME/godot-$GODOT_VERSION-stable" "$HOME/.local/bin/godot"

# 10. Claude Code CLI
echo -e "${YELLOW}[10/10] Установка Claude Code CLI...${NC}"
if ! command -v claude > /dev/null; then
  curl -fsSL https://claude.ai/install.sh | bash 2>&1 | grep -v "^Download\|^Extract" || \
    echo -e "${YELLOW}Claude Code CLI уже установлен или ошибка установки (проверьте вручную)${NC}"
fi

# 11. Клон репозитория и настройка
if [ "$ANDROID_ONLY" -eq 0 ]; then
  echo -e "${YELLOW}[11/12] Клонирование репозитория...${NC}"
  REPO_URL="${REPO_URL:-git@github.com:Gornist/megablock10.git}"
  REPO_DIR="${REPO_DIR:-$HOME/megablock10}"
  if [ ! -d "$REPO_DIR/.git" ]; then
    git clone "$REPO_URL" "$REPO_DIR" || echo -e "${RED}Ошибка при клонировании репозитория${NC}"
  fi

  # local.properties для Gradle
  if [ -d "$REPO_DIR" ]; then
    echo -e "${YELLOW}[12/12] Создание local.properties...${NC}"
    cat > "$REPO_DIR/local.properties" << EOF
sdk.dir=$ANDROID_HOME
ndk.dir=$ANDROID_HOME/ndk/28.1.13356709
EOF

    # Git хуки
    echo "Установка Git хуков..."
    if [ -x "$REPO_DIR/scripts/setup-hooks.sh" ]; then
      bash "$REPO_DIR/scripts/setup-hooks.sh" 2>&1 | grep -v "^Setting\|^Hook" || true
    fi

    # Зависимости коллектора: без них check.sh падает на «tsx: not found»
    echo "Установка зависимостей admin-web (npm ci)..."
    for m in server client; do
      (cd "$REPO_DIR/admin-web/$m" && npm ci --no-audit --no-fund --silent) || echo -e "${RED}npm ci в admin-web/$m не прошёл${NC}"
    done
  fi
fi

# 12. Проверки
echo -e "${GREEN}=== Проверка установки ===${NC}"

echo -n "kvm-ok: "
kvm-ok 2>/dev/null || echo "Не установлен или нет поддержки KVM"

echo -n "java (17): "
"$JAVA17_HOME/bin/java" -version 2>&1 | head -1 || echo "Ошибка"

echo -n "java (21): "
"$JAVA21_HOME/bin/java" -version 2>&1 | head -1 || echo "Ошибка"

echo -n "sdkmanager: "
"$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --list_installed 2>/dev/null | head -3 || echo "Ошибка"

echo -n "godot: "
"$GODOT_HOME/godot-$GODOT_VERSION-stable" --version 2>/dev/null || echo "Ошибка"

echo -n "node: "
node -v

echo -n "npm: "
npm -v

echo -e "${GREEN}=== Настройка завершена ===${NC}"
echo ""
echo -e "${YELLOW}Рекомендации:${NC}"
echo "1. Добавьте в ~/.bashrc или ~/.zshrc:"
echo "   export ANDROID_HOME=$ANDROID_HOME"
echo "   export ANDROID_SDK_ROOT=$ANDROID_HOME"
echo "   export JAVA_HOME=$JAVA21_HOME"
echo "   export PATH=\$HOME/.local/bin:\$PATH"
echo ""
echo "2. После нового входа проверьте членство в группе kvm:"
echo "   id -nG | grep kvm"
echo ""
echo "3. Клонируйте репозиторий (если не был клонирован):"
echo "   git clone $REPO_URL"
echo ""
echo "4. Запустите проверку сборки:"
echo "   cd megablock10 && ./scripts/check.sh --fast"
echo ""
