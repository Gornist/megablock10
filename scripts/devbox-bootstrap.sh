#!/usr/bin/env bash
# Первичная настройка devbox на ЧИСТОЙ Ubuntu 26.04 Desktop (одна система на весь диск, 25.10.2026). Идемпотентно, можно перезапускать.
# Требования до запуска (руками, в установщике): пользователь `nick`, имя машины `devbox` (скрипты сверяют `hostname -s` с devbox),
# сеть по кабелю, ssh-ключ Mac в ~/.ssh/authorized_keys (на Mac: ssh-copy-id nick@<адрес>; пароль вводит владелец).
#
#   Mac:    rsync -a scripts/ nick@<адрес>:bootstrap/scripts/
#   devbox: sudo bash ~/bootstrap/scripts/devbox-bootstrap.sh          # пароль sudo вводит владелец; ~15–30 мин, нужен интернет
#   затем:  sudo reboot (драйвер NVIDIA), с Mac — scripts/box.sh sync (клон ~/box/repo, службы, автозапуск), scripts/box.sh status
#
# Что делает: пакеты и драйвер NVIDIA 595 (open), Docker, Temurin 17/21, Android SDK (cmdline-tools, platform-tools, platform 37,
# build-tools 36.0.0, emulator), Godot 4.7.2 и Blender 4.5.14 в ~/.local, автовход nick в GNOME без блокировки и сна, linger для
# user-служб, права на USB/KVM, `devjob`. Чего НЕ делает: Tailscale и VPN (убраны), секреты и ключи (возвращает владелец из копии
# ~/Developer/devbox-backup-1025 на Mac), экспортные шаблоны Godot, образы эмулятора e2e и всё из зон Godot/Blender (они доустановят сами).
set -u

[ "$(id -u)" = 0 ] || { echo "нужен sudo: sudo bash $0"; exit 1; }
U=${SUDO_USER:-nick}
H=$(getent passwd "$U" | cut -d: -f6)
HERE=$(cd "$(dirname "$0")" && pwd)
[ "$U" = nick ] || { echo "пользователь должен быть nick (пути /home/nick зашиты в скриптах), а не $U"; exit 1; }
as_user() { sudo -u "$U" -H bash -c "$*"; }
step() { echo; echo "=== $*"; }
FAILED=()
try() { "$@" || { FAILED+=("$*"); echo "!! не вышло: $*"; }; }

step "имя машины и сон"
hostnamectl set-hostname devbox
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target >/dev/null 2>&1
loginctl enable-linger "$U"

step "apt: базовые пакеты"
export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a
# без вопросов и без ввода с терминала: в `ssh -t … | tee` apt, ждущий ответа, получает SIGTTIN и висит в состоянии T (25.10.2026, 15 минут впустую)
apt_install() { apt-get install -y -qq -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold "$@" </dev/null; }
apt-get update -qq </dev/null
try apt_install build-essential ca-certificates curl wget git gnupg unzip zip rsync jq python3 python3-pip nodejs npm \
  openssh-server docker.io qemu-system-x86 cpu-checker tesseract-ocr vainfo intel-media-va-driver-non-free \
  android-sdk-platform-tools-common flatpak shellcheck xz-utils efibootmgr zstd \
  qemu-user-static binfmt-support   # эмуляция arm64 для сборки образов Raspberry Pi (Шерегеш): binfmt qemu-aarch64 с флагом F после каждой загрузки
systemctl enable --now ssh docker >/dev/null 2>&1
usermod -aG docker,plugdev,kvm,dialout "$U"

step "драйвер NVIDIA 595 (open)"
try apt_install nvidia-driver-595-open

step "Temurin 17 и 21 (репозиторий Adoptium)"
mkdir -p /etc/apt/keyrings
curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public -o /etc/apt/keyrings/adoptium.asc
echo "deb [signed-by=/etc/apt/keyrings/adoptium.asc] https://packages.adoptium.net/artifactory/deb $(. /etc/os-release; echo "$VERSION_CODENAME") main" \
  >/etc/apt/sources.list.d/adoptium.list
apt-get update -qq </dev/null
try apt_install temurin-17-jdk temurin-21-jdk

step "автовход nick (GDM) — графический сеанс нужен Blender, Godot и автозапуску"
CONF=/etc/gdm3/custom.conf
if [ -f "$CONF" ] && ! grep -q '^AutomaticLogin=' "$CONF"; then
  sed -i "s/^\[daemon\]/[daemon]\nAutomaticLoginEnable=true\nAutomaticLogin=$U/" "$CONF"
fi
as_user "gsettings set org.gnome.desktop.screensaver lock-enabled false; gsettings set org.gnome.desktop.session idle-delay 0; \
  gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type nothing" 2>/dev/null || echo "gsettings: нет сеанса — повторить после первого входа"

step "Android SDK в ~/android-sdk"
SDK=$H/android-sdk
if [ ! -x "$SDK/cmdline-tools/latest/bin/sdkmanager" ]; then
  as_user "mkdir -p $SDK/cmdline-tools && cd /tmp && curl -fsSL -o cmdtools.zip https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip \
    && unzip -q -o cmdtools.zip -d $SDK/cmdline-tools && rm -rf $SDK/cmdline-tools/latest && mv $SDK/cmdline-tools/cmdline-tools $SDK/cmdline-tools/latest && rm cmdtools.zip"
fi
as_user "export JAVA_HOME=/usr/lib/jvm/temurin-21-jdk-amd64; yes | $SDK/cmdline-tools/latest/bin/sdkmanager --licenses >/dev/null 2>&1; \
  $SDK/cmdline-tools/latest/bin/sdkmanager 'platform-tools' 'platforms;android-37.0' 'build-tools;36.0.0' 'emulator'" || FAILED+=("sdkmanager")

step "Godot 4.7.2 и Blender 4.5.14 в ~/.local"
as_user "mkdir -p ~/.local/bin ~/.local/godot ~/.local/blender-dl"
if [ ! -x "$H/.local/godot/godot-4.7.2-stable" ]; then
  as_user "cd /tmp && curl -fsSL -o godot.zip https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/Godot_v4.7.2-stable_linux.x86_64.zip \
    && unzip -q -o godot.zip -d ~/.local/godot && mv ~/.local/godot/Godot_v4.7.2-stable_linux.x86_64 ~/.local/godot/godot-4.7.2-stable && rm godot.zip \
    && ln -sf ~/.local/godot/godot-4.7.2-stable ~/.local/bin/godot" || FAILED+=("godot")
fi
if [ ! -x "$H/.local/blender/blender" ]; then
  as_user "cd /tmp && curl -fsSL -o blender.tar.xz https://download.blender.org/release/Blender4.5/blender-4.5.14-linux-x64.tar.xz \
    && rm -rf ~/.local/blender && mkdir -p ~/.local/blender && tar -xJf blender.tar.xz -C ~/.local/blender --strip-components=1 && rm blender.tar.xz \
    && ln -sf ~/.local/blender/blender ~/.local/bin/blender" || FAILED+=("blender")
fi

step "devjob, каталоги"
as_user "mkdir -p ~/jobs ~/box ~/.local/state"
[ -f "$HERE/box/devjob" ] && install -m 755 -o "$U" -g "$U" "$HERE/box/devjob" "$H/.local/bin/devjob" || echo "нет $HERE/box/devjob — положить руками"

step "PATH для неинтерактивного ssh (adb и инструменты находятся без входа в сеанс)"
if ! grep -q 'box-adb-path' "$H/.bashrc"; then
  # блок ставится В НАЧАЛО ~/.bashrc, над проверкой интерактивности (иначе неинтерактивный ssh его не увидит); 25.10 вариант через
  # sed '4r' молча не вставился — теперь через временный файл и mv, с проверкой
  BP=$(mktemp)
  {
    echo '# >>> box-adb-path (неинтерактивный ssh: adb и ~/.local/bin; в конец PATH) >>>'
    # shellcheck disable=SC2016  # раскрывается при чтении ~/.bashrc, не здесь
    echo 'for d in $HOME/android-sdk/platform-tools $HOME/.local/bin; do case :$PATH: in *:$d:*) ;; *) PATH=$PATH:$d;; esac; done'
    echo '# <<< box-adb-path <<<'
    echo
    cat "$H/.bashrc"
  } >"$BP" && install -m 644 -o "$U" -g "$U" "$BP" "$H/.bashrc"
  rm -f "$BP"
  grep -q box-adb-path "$H/.bashrc" || FAILED+=("bashrc: блок PATH не вставился")
fi
as_user 'grep -q "ANDROID_HOME" ~/.bashrc || cat >> ~/.bashrc <<EOF
# >>> devbox-setup >>>
export ANDROID_HOME=\$HOME/android-sdk
export ANDROID_SDK_ROOT=\$ANDROID_HOME
export JAVA_HOME=/usr/lib/jvm/temurin-21-jdk-amd64
export PATH=\$HOME/.local/bin:\$JAVA_HOME/bin:\$ANDROID_HOME/cmdline-tools/latest/bin:\$ANDROID_HOME/platform-tools:\$ANDROID_HOME/emulator:\$PATH
# <<< devbox-setup <<<
EOF'

step "snap-store и лишнее"
snap remove --purge snap-store >/dev/null 2>&1 || true

echo
if [ ${#FAILED[@]} -gt 0 ]; then
  echo "ИТОГ: есть сбои — ${FAILED[*]}"; exit 1
fi
echo "ИТОГ: ok. Дальше: sudo reboot; с Mac — scripts/box.sh sync, затем вернуть ключи и службы из ~/Developer/devbox-backup-1025 (README там)."
