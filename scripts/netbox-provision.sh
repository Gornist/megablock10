#!/usr/bin/env bash
# Окружение Сети (Godot, Blender, сборка APK, очки Pico) на хосте Сети — 3060pc, рабочем ПК владельца (перенос с devbox 14.11.2026,
# docs/devbox.md «Хост Сети»). Запускать НА самой машине из клона репозитория: bash scripts/netbox-provision.sh. Идемпотентно; итог — строка ИТОГ.
# Повторяет нужную часть scripts/devbox-bootstrap.sh БЕЗ драйвера NVIDIA, Docker, KVM, автовхода, отключения сна и блокировки и без
# системных и user-служб (box-adb, страж очков, автозапуск Godot AI): это рабочий стол владельца, а не выделенный стенд.
# Пользователь — любой (не nick), sudo нужен только для apt. Загрузки — ~/bootstrap/dl (докачка).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
DL=$HOME/bootstrap/dl
SDK=$HOME/android-sdk
mkdir -p "$DL" "$HOME/.local/bin" "$HOME/.local/godot"
FAILED=()
step() { echo; echo "== $*"; }
fetch() {  # fetch файл url — докачка, без повторной загрузки готового
  local f=$1 u=$2
  [ -s "$DL/$f.ok" ] && return 0
  curl -fL --retry 5 --retry-delay 5 -C - -o "$DL/$f" "$u" && echo ok > "$DL/$f.ok"
}

step "apt: Temurin 17, udev-правила adb, unzip"
if ! dpkg -s temurin-17-jdk >/dev/null 2>&1; then
  sudo install -d -m 755 /etc/apt/keyrings
  sudo curl -fsSL https://packages.adoptium.net/artifactory/api/gpg/key/public -o /etc/apt/keyrings/adoptium.asc
  echo "deb [signed-by=/etc/apt/keyrings/adoptium.asc] https://packages.adoptium.net/artifactory/deb $(. /etc/os-release; echo "$VERSION_CODENAME") main" \
    | sudo tee /etc/apt/sources.list.d/adoptium.list >/dev/null
  sudo apt-get update -qq || true
fi
# python3-pil — сетки кадров dev.sh shot и pipeline.sh (Pillow); rsync — синхронизация с Mac.
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq temurin-17-jdk android-sdk-platform-tools-common unzip xz-utils python3-pil rsync >/dev/null \
  || FAILED+=("apt")
[ -x /usr/lib/jvm/temurin-17-jdk-amd64/bin/java ] || FAILED+=("temurin-17")

step "Godot 4.7.2"
GZ=Godot_v4.7.2-stable_linux.x86_64.zip
if [ ! -x "$HOME/.local/godot/godot-4.7.2-stable" ]; then
  fetch "$GZ" "https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/$GZ" \
    && unzip -q -o "$DL/$GZ" -d "$HOME/.local/godot" \
    && mv "$HOME/.local/godot/Godot_v4.7.2-stable_linux.x86_64" "$HOME/.local/godot/godot-4.7.2-stable" \
    && ln -sf "$HOME/.local/godot/godot-4.7.2-stable" "$HOME/.local/bin/godot" || FAILED+=("godot")
fi

step "Blender 4.5.14"
BT=blender-4.5.14-linux-x64.tar.xz
if [ ! -x "$HOME/.local/blender/blender" ]; then
  fetch "$BT" "https://download.blender.org/release/Blender4.5/$BT" \
    && rm -rf "$HOME/.local/blender" && mkdir -p "$HOME/.local/blender" \
    && tar -xJf "$DL/$BT" -C "$HOME/.local/blender" --strip-components=1 \
    && ln -sf "$HOME/.local/blender/blender" "$HOME/.local/bin/blender" || FAILED+=("blender")
fi

step "uv 0.13.5"
UT=uv-x86_64-unknown-linux-gnu.tar.gz
if [ ! -x "$HOME/.local/bin/uv" ]; then
  fetch "$UT" "https://github.com/astral-sh/uv/releases/download/0.13.5/$UT" \
    && tar -xzf "$DL/$UT" -C "$DL" && install -m 755 "$DL"/uv-x86_64-unknown-linux-gnu/uv "$DL"/uv-x86_64-unknown-linux-gnu/uvx "$HOME/.local/bin/" \
    || FAILED+=("uv")
fi

step "Android SDK (cmdline-tools, platform-tools, android-37.0, build-tools 36.0.0)"
if [ ! -x "$SDK/cmdline-tools/latest/bin/sdkmanager" ]; then
  CT=commandlinetools-linux-11076708_latest.zip
  fetch "$CT" "https://dl.google.com/android/repository/$CT" \
    && mkdir -p "$SDK/cmdline-tools" && rm -rf "$SDK/cmdline-tools/latest" "$DL/cmdline-tools" \
    && unzip -q -o "$DL/$CT" -d "$DL" && mv "$DL/cmdline-tools" "$SDK/cmdline-tools/latest" || FAILED+=("cmdline-tools")
fi
if [ -x "$SDK/cmdline-tools/latest/bin/sdkmanager" ] && { [ ! -x "$SDK/platform-tools/adb" ] || [ ! -d "$SDK/build-tools/36.0.0" ]; }; then
  export JAVA_HOME=/usr/lib/jvm/temurin-17-jdk-amd64
  yes | "$SDK/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$SDK" --licenses >/dev/null 2>&1
  "$SDK/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$SDK" 'platform-tools' 'platforms;android-37.0' 'build-tools;36.0.0' >/dev/null \
    || FAILED+=("sdkmanager")
fi

step "Шаблоны экспорта Godot 4.7.2 (1,28 ГБ)"
TPZ=Godot_v4.7.2-stable_export_templates.tpz
TPL=$HOME/.local/share/godot/export_templates/4.7.2.stable
if [ ! -f "$TPL/android_source.zip" ]; then
  if fetch "$TPZ" "https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable/$TPZ"; then
    SUM=$(sha256sum "$DL/$TPZ" | cut -c1-64)
    case "$SUM" in
      f298490b*8011) echo "sha256 совпадает с docs/devbox.md (f298490b…8011)";;
      *) echo "sha256 НЕ совпадает: $SUM"; FAILED+=("templates-sha");;
    esac
    if [ "${SUM:0:8}" = f298490b ]; then
      mkdir -p "$HOME/.local/share/godot/export_templates" && rm -rf "$DL/tpl" && mkdir "$DL/tpl" \
        && unzip -q -o "$DL/$TPZ" -d "$DL/tpl" && rm -rf "$TPL" && mv "$DL/tpl/templates" "$TPL" || FAILED+=("templates-unpack")
    fi
  else
    FAILED+=("templates-download")
  fi
fi

step "netrun-env.sh и PATH для неинтерактивного ssh"
if [ ! -f "$HOME/netrun-env.sh" ]; then
  printf '%s\n' 'export JAVA_HOME=/usr/lib/jvm/temurin-17-jdk-amd64' 'export ANDROID_HOME=$HOME/android-sdk' \
    'export PATH=$HOME/.local/bin:$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH' > "$HOME/netrun-env.sh"
fi
if ! grep -q 'box-adb-path' "$HOME/.bashrc"; then
  BP=$(mktemp)
  {
    echo '# >>> box-adb-path (неинтерактивный ssh: adb и ~/.local/bin; в конец PATH) >>>'
    echo 'for d in $HOME/android-sdk/platform-tools $HOME/.local/bin; do case :$PATH: in *:$d:*) ;; *) PATH=$PATH:$d;; esac; done'
    echo '# <<< box-adb-path <<<'
    echo
    cat "$HOME/.bashrc"
  } > "$BP" && cp "$HOME/.bashrc" "$HOME/.bashrc.bak-provision" && mv "$BP" "$HOME/.bashrc"
  grep -q box-adb-path "$HOME/.bashrc" || FAILED+=("bashrc")
fi

step "devjob (долгие задачи отдельно от ssh)"
install -m 755 "$HERE/box/devjob" "$HOME/.local/bin/devjob" || FAILED+=("devjob")

step "Проверка"
"$HOME/.local/bin/godot" --version 2>/dev/null | head -1 || FAILED+=("godot-run")
"$HOME/.local/bin/blender" --version 2>/dev/null | head -1 || FAILED+=("blender-run")
/usr/lib/jvm/temurin-17-jdk-amd64/bin/java -version 2>&1 | head -1
"$SDK/platform-tools/adb" version 2>/dev/null | head -1 || FAILED+=("adb-run")
find "$TPL" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | sed 's/^ */шаблонов: /'
python3 -c 'import PIL; print("Pillow", PIL.__version__)' || FAILED+=("pillow")
du -sh "$DL" 2>/dev/null | sed 's/^/загрузки: /'

if [ ${#FAILED[@]} -eq 0 ]; then echo "ИТОГ: ОК"; else echo "ИТОГ: ОШИБКИ: ${FAILED[*]}"; exit 1; fi
