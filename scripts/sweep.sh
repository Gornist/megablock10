#!/bin/bash
# Обход сессий и очков без модели (решение владельца 14.10: «обход без лишней траты токенов»). Раньше Pipeline manager раз в
# 15 мин сам ходил по сессиям и очкам — каждый ход стоил токенов на весь контекст, даже когда всё в порядке (десятки «обход: ок» за ночь).
# Теперь проверки делает скрипт, а модель будится только по находке.
#   scripts/sweep.sh            — один проход: печатает находки (по строке), код 0 — пусто, 1 — есть находки
#   scripts/sweep.sh --watch [мин] — проход каждые N мин (по умолчанию 5) в фоне; выходит на первой находке (одно уведомление)
# Находки:
#   - очки Awake без брони — гасит сам (box.sh pico sleep Pipeline) и сообщает;
#   - новая строка «нужен человек» в ~/box/attention.log на devbox;
#   - замечания `box.sh status` (лишний adb-сервер, запаркованная карточка);
#   - сессия Claude Code проекта, у которой последний ход оборвался ошибкой API или отказом классификатора.
# Уже сообщённое не повторяется: состояние в ~/.cache/mb10-sweep/.
set -u
ST=$HOME/.cache/mb10-sweep; mkdir -p "$ST"
BOX='$HOME/box/repo/scripts/box.sh'   # раскрывается на devbox, не здесь

once() {
  local found="" s n f last key why
  # Очки и devbox — одним ssh: статус очков, новые строки attention.log, замечания статуса.
  s=$(ssh -o ConnectTimeout=10 devbox "echo P:\$($BOX pico status 2>&1 | head -1); echo N:\$(wc -l < ~/box/attention.log 2>/dev/null); $BOX status 2>&1 | grep -iE 'лишн|паркован|замечани' | sed 's/^/W:/'" 2>/dev/null) ||
    { echo "SWEEP: devbox недоступен"; return 1; }
  local pico; pico=$(sed -n 's/^P://p' <<<"$s")
  if grep -q 'Awake' <<<"$pico" && ! grep -q 'бронь' <<<"$pico"; then
    ssh devbox "$BOX pico sleep Pipeline" >/dev/null 2>&1
    found="$found\nочки горели без брони — погашены"
  fi
  n=$(sed -n 's/^N:\([0-9]*\).*/\1/p' <<<"$s"); n=${n:-0}
  local seen; seen=$(cat "$ST/attention" 2>/dev/null || echo "$n")
  if [ "$n" -gt "$seen" ]; then
    found="$found\n$(ssh devbox "tail -n $((n - seen)) ~/box/attention.log" 2>/dev/null | jq -r '"нужен человек: \(.reason) — \(.todo // "")"' 2>/dev/null | cut -c1-200)"
  fi
  echo "$n" >"$ST/attention"
  local warn; warn=$(sed -n 's/^W://p' <<<"$s" | head -2)
  if [ -n "$warn" ] && [ "$warn" != "$(cat "$ST/warn" 2>/dev/null)" ]; then found="$found\ndevbox: $warn"; fi
  printf '%s' "$warn" >"$ST/warn"
  # Сессии: последний ход в журнале — ошибка API или отказ классификатора. Только журналы, менявшиеся за 3 ч.
  while IFS= read -r f; do
    last=$(grep -E '"type":"(assistant|user)"' -- "$f" | tail -1)
    # Признак — поля записи, а не текст: в журнале Pipeline эти слова встречаются в самом скрипте (ложная находка 14.10).
    why=$(jq -r 'if .isApiErrorMessage == true then "ошибка API: \(.error // "") \(.message.content[0].text // "" | .[0:60])"
      elif (.type == "user" and ((.message.content | type) == "array") and (.message.content[0].is_error == true)
            and ((.message.content[0].content | tostring) | test("auto mode classifier|temporarily unavailable"))) then
        "отказ классификатора" else empty end' <<<"$last" 2>/dev/null)
    [ -n "$why" ] || continue
    key=$(basename "$f" .jsonl):$(jq -r '.uuid // empty' <<<"$last" 2>/dev/null)
    grep -qxF "$key" "$ST/sessions" 2>/dev/null && continue
    echo "$key" >>"$ST/sessions"
    found="$found\nсессия $(basename "$f" .jsonl | cut -c1-8) ($(jq -r '.cwd // "?"' <<<"$last" | sed "s|$HOME/||")): $why"
  done < <(find "$HOME/.claude/projects" -maxdepth 2 -name '*.jsonl' -mmin -180 \( -path '*megablock10*' -o -path '*larphouse*' \) 2>/dev/null)
  [ -z "$found" ] && return 0
  printf '%b\n' "$found" | sed '/^$/d' | sed 's/^/SWEEP: /'
  return 1
}

if [ "${1:-}" = --watch ]; then
  mins=${2:-5}
  for _ in $(seq 1 576); do          # предел ≈ 48 ч при 5 мин
    once && { for _ in $(seq 1 $((mins * 2))); do sleep 30; done; continue; }
    exit 1
  done
  echo "SWEEP: предел итераций — перезапустить"; exit 0
fi
once
