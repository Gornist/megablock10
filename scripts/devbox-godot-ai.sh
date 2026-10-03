#!/usr/bin/env bash
# Редактор Godot с плагином Godot AI (MCP) на devbox — на реальном дисплее GNOME (:0, GTX 1650).
# Запускать НА devbox: scripts/devbox-godot-ai.sh setup|start|stop|status|autostart
#
# Что и где (docs/netrun-devbox.md, «Godot AI»):
#   * рабочая копия — git worktree ~/wt-godot на ветке agent/godot (от agent/netrun): агент правит сцены прямо в ней,
#     правки видны в `git diff` и уходят обычным коммитом; свой каталог/ветка — GODOT_AI_WT / GODOT_AI_BRANCH;
#   * плагин (addons/godot_ai) в репозиторий не кладём (в .gitignore): он правит project.godot и открывает порты.
#     start дописывает в project.godot три строки (плагин, автозагрузка хелпера, аргументы игры), stop их снимает —
#     чтобы они не попали в коммит и экспорт APK;
#   * клиент (Claude Code на Mac) ходит через `uvx godot-ai attach` по ssh — .mcp.json в корне репозитория, токены не нужны.
# Ловушки, на которых уже обожглись:
#   * процесс редактора берём из pid-файла: `pkill -f`/`ps | grep` по «godot --editor» совпадает с самой ssh-командой
#     и убивает сессию;
#   * сервер MCP — дочерний у редактора; после остановки ждём освобождения портов 8000/9500, lock-файл
#     ~/.config/godot-ai/capabilities не трогаем — иначе плагин пишет «server start blocked» и не подключается.
set -euo pipefail

CMD="${1:-status}"
PLUGIN_VERSION="${GODOT_AI_VERSION:-4.2.3}"
PLUGIN_SHA256="${GODOT_AI_SHA256:-bff05c143e1061842f4a9f2c415331616227967eaba1ac6d180fed5172cdb417}"  # godot-ai-v4-plugin.zip v4.2.3
REPO="${GODOT_AI_REPO:-$HOME/megablock10}"
WT="${GODOT_AI_WT:-$HOME/wt-godot}"
BRANCH="${GODOT_AI_BRANCH:-agent/godot}"
BASE_BRANCH="${GODOT_AI_BASE:-agent/netrun}"
PROJECT="$WT/netrun"
PIDFILE="$HOME/.godot-ai-editor.pid"
LOG="$WT/.godot-ai-editor.log"
# Аргументы игры при project_run: плоский клиент к локальному серверу мира (после «--» — пользовательские).
RUN_ARGS="${GODOT_AI_RUN_ARGS:--- --flat --host=127.0.0.1 --port=7777 --token=t1}"

editor_alive() { [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; }
env_load() {
  # shellcheck disable=SC1091
  . "$HOME/netrun-env.sh"
  export PATH="$HOME/.local/bin:$PATH"
}

# patch_project on|off — три строки плагина в project.godot (идемпотентно).
patch_project() {
  python3 - "$PROJECT/project.godot" "$1" "$RUN_ARGS" <<'PY'
import re, sys
path, mode, run_args = sys.argv[1:4]
text = open(path, encoding="utf-8").read()
PLUGIN = "res://addons/godot_ai/plugin.cfg"
AUTOLOAD = '_mcp_game_helper="*res://addons/godot_ai/runtime/game_helper.gd"'

def plugins_line(t):
    m = re.search(r'^enabled=PackedStringArray\((.*)\)$', t, re.M)
    return m

if mode == "on":
    m = plugins_line(text)
    if m is None:
        text = text.rstrip("\n") + '\n\n[editor_plugins]\n\nenabled=PackedStringArray("%s")\n' % PLUGIN
    elif PLUGIN not in m.group(1):
        text = text[:m.start(1)] + m.group(1) + ', "%s"' % PLUGIN + text[m.end(1):]
    if "_mcp_game_helper=" not in text:
        if "\n[autoload]\n" in text:
            text = text.replace("\n[autoload]\n", "\n[autoload]\n\n" + AUTOLOAD + "\n", 1)
        else:
            text = text.rstrip("\n") + "\n\n[autoload]\n\n" + AUTOLOAD + "\n"
    line = 'run/main_run_args="%s"' % run_args
    if re.search(r'^run/main_run_args=', text, re.M):
        text = re.sub(r'^run/main_run_args=.*$', line, text, flags=re.M)
    elif "\n[editor]\n" in text:
        text = text.replace("\n[editor]\n", "\n[editor]\n\n" + line + "\n", 1)
    else:
        text = text.rstrip("\n") + "\n\n[editor]\n\n" + line + "\n"
else:
    m = plugins_line(text)
    if m is not None:
        items = [i.strip() for i in m.group(1).split(",") if i.strip() and PLUGIN not in i]
        if items:
            text = text[:m.start(1)] + ", ".join(items) + text[m.end(1):]
        else:  # раздел, который завели мы, — убираем целиком
            text = re.sub(r'\n?\[editor_plugins\]\n+enabled=PackedStringArray\(\)\n?', "\n", text)
    text = re.sub(r'^_mcp_game_helper=.*\n?', "", text, flags=re.M)
    text = re.sub(r'^run/main_run_args=.*\n?', "", text, flags=re.M)
    text = re.sub(r'\n\[editor\]\n+(?=\n\[|\Z)', "\n", text)
    text = re.sub(r'\n\[autoload\]\n+(?=\n\[|\Z)', "\n", text)
    text = re.sub(r'\n{3,}', "\n\n", text)
open(path, "w", encoding="utf-8").write(text)
PY
}

case "$CMD" in
  setup)  # один раз: worktree, плагин, импорт проекта
    env_load
    if [[ ! -d "$WT/.git" && ! -f "$WT/.git" ]]; then
      if git -C "$REPO" rev-parse --verify -q "$BRANCH" >/dev/null; then
        git -C "$REPO" worktree add "$WT" "$BRANCH"
      else
        git -C "$REPO" worktree add -b "$BRANCH" "$WT" "$BASE_BRANCH"
      fi
    fi
    if [[ ! -f "$PROJECT/addons/godot_ai/plugin.cfg" ]]; then
      tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
      curl -fsSL -o "$tmp/p.zip" "https://github.com/hi-godot/godot-ai/releases/download/v${PLUGIN_VERSION}/godot-ai-v4-plugin.zip"
      echo "$PLUGIN_SHA256  $tmp/p.zip" | sha256sum -c - >/dev/null || { echo "sha256 плагина не сошёлся" >&2; exit 1; }
      unzip -q "$tmp/p.zip" -d "$PROJECT"
    fi
    ( cd "$PROJECT" && godot --headless --path . --import >/dev/null 2>&1 || true )
    echo "готово: $PROJECT (ветка $BRANCH)" ;;
  start)
    editor_alive && { echo "уже запущен, pid $(cat "$PIDFILE")"; exit 0; }
    [[ -f "$PROJECT/addons/godot_ai/plugin.cfg" ]] || { echo "нет плагина в $PROJECT — сначала: $0 setup" >&2; exit 1; }
    env_load
    export DISPLAY=:0
    XAUTHORITY="$(ls /run/user/"$(id -u)"/.mutter-Xwaylandauth.* | head -1)"; export XAUTHORITY
    export GODOT_AI_DISABLE_TELEMETRY=1   # на площадке интернета нет, да и незачем
    patch_project on
    cd "$PROJECT"
    nohup godot --editor --path . >"$LOG" 2>&1 </dev/null &
    echo $! >"$PIDFILE"
    for _ in $(seq 1 30); do
      sleep 3
      grep -aq "authenticated with server" "$LOG" && { echo "готово: редактор pid $(cat "$PIDFILE"), клиент — uvx godot-ai attach"; exit 0; }
      grep -aq "server start blocked" "$LOG" && { echo "плагин не поднял сервер, см. $LOG; остановите (stop) и повторите" >&2; exit 1; }
    done
    echo "не дождались подключения плагина, см. $LOG" >&2; exit 1 ;;
  stop)
    if editor_alive; then
      kill "$(cat "$PIDFILE")"
      for _ in $(seq 1 10); do ss -ltn | grep -qE ':(8000|9500) ' || break; sleep 3; done
    fi
    rm -f "$PIDFILE"
    [[ -f "$PROJECT/project.godot" ]] && patch_project off
    echo "остановлен, строки плагина из project.godot сняты"
    # Редактор сам переписывает project.godot при открытии (комментарии, значения по умолчанию) — это шум.
    if [[ -d "$WT" ]] && ! git -C "$WT" diff --quiet -- netrun/project.godot; then
      echo "ВНИМАНИЕ: netrun/project.godot отличается от HEAD. Правок настроек не делали — откатите: git -C $WT checkout netrun/project.godot" >&2
    fi ;;
  status)
    if editor_alive; then echo "редактор pid $(cat "$PIDFILE"), проект $PROJECT"; ss -ltn | grep -E ':(8000|9500) ' || true
    else echo "не запущен"; fi ;;
  autostart)  # поднимать редактор при входе nick в GNOME (нужен графический сеанс)
    mkdir -p "$HOME/.config/autostart"
    cat >"$HOME/.config/autostart/godot-ai.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Godot AI
Exec=bash -c 'sleep 20; $REPO/scripts/devbox-godot-ai.sh start'
X-GNOME-Autostart-enabled=true
EOF
    echo "автозапуск включён (~/.config/autostart/godot-ai.desktop)" ;;
  *) echo "использование: $0 setup|start|stop|status|autostart" >&2; exit 2 ;;
esac
