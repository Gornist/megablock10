---
name: blender-netrun-env-state
description: "Состояние работы Blender-сессии над видом Сети на 07.10.2026 — что влито, открытый PR 87, решения владельца, ждущие вопросы, как продолжить после /clear"
metadata:
  node_type: memory
  type: project
  originSessionId: 714a5d95-4ee3-44c4-b1be-8bd46d0e3b79
  modified: 2026-10-07T06:12:03.057Z
---

Blender-сессия (вид Сети, `netrun/assets/**` + тесты `netrun/tests/assets_*`, зона и правила — [[blender-session-zone]]). Цикл и грабли теперь в skill `netrun-assets` (`.claude/skills/netrun-assets/`, PR 82 влит) — читать его первым.

**Влито в main:** PR 21 (окружение «волюметрик», пол одним тайлом, предметы узла vault/shard/token/hack_panel/hack_pad, pipeline.sh flock/--grid/детерминизм), PR 73→82 (`pipeline.sh stats` + `framestats.py` + skill).
**Открыто:** PR 87 `agent/void-exit-beacon` (worktree `/Users/peachbite/Developer/megablock10-wt/void-exit-beacon`): фон `AssetMaterials.VOID_BG` (0,0.10,0.13), `env/exit_frame`, узел `Beacon` у shard/shard_encrypted/daemon_token. CI ждал `scripts/ci-wait.sh pr 87`; статус BEHIND (main ушёл) — перед слиянием нужен `origin/main` в ветку (это делает Pipeline, он ведёт очередь слияний). После «готово к слиянию» Pipeline владелец запускает `land.sh`; после «влит» — новая worktree (`scripts/agent-worktree.sh new <имя>`), старую не продолжать.

**Решения владельца (все 5–6 окт):** пол комнаты — ОДИН чёрный тайл `env/floor_slab_16` (плитки/стекло/floor_v1–4 — эксперименты, в клиент не идут); стены убраны (WALLS_ENABLED=false в клиенте; в просмотре `--walls`); границу даёт `room_edge_16` (без точек, дымка 0,6, до колена); ров не нужен (`room_moat_*` не использовать); красного в окружении нет; стиль — штрихи, вуаль, дымка, тонкие плиты 3 см; интерактивное — чёткий силуэт внутри мягкой оболочки; ничего выше пола.
**Ждут решения владельца:** чуть приподнять цвет чёрных плит solid_dark, чтобы чистого чёрного стало ≈0 как у референса (сейчас dark 13–31 % против ≈0); читаемость exit_frame на кадре слабая; проём exit_frame 1,04×2 м взят у lockdown_gate (шире 1,6×2,4 — пересобирать ворота); замер на Pico 4 (за Godot-сессией, «очки свободны») — слоёв прозрачности много (ореол, вуаль, дымка, Beacon, 4 слоя у расшифрованного шарда).
**Передать Godot-сессии после слияния 87 (она уже интегрировала PR 21 в ветке agent/env-integ):** `Environment.background_color = AssetMaterials.VOID_BG`; `env/exit_frame` вместо `doorway`, при LOCKDOWN `lockdown_gate`; `Beacon.visible=false`, когда предмет в руке/в деке, AABB без Beacon; панель взлома/площадка/vault Tier и shard Tier подключает она отдельным шагом (ориентация vault: «перед» Godot −Z, клиент ставит yaw+PI).

**Референсы владельца (Cyberpunk 2077, Blackwall/киберпространство, автор Peter Ankermann/CDPR):** 6 кадров сохранены ВНЕ git в `memory/netrun-refs/{1..6}.webp` (2 — человек в киберпространстве, 4 — «дождь» штрихов и дымка на горизонте, 6 — ступенчатые террасы). Числа по ним (`pipeline.sh stats`): lum 19–25, dark≈0, cyan 96–98 %, hor 1,4–1,9, topbot 0,4–0,6.

**Как работать (напоминание):** исполнителей-sonnet запускать по одному (devbox один, pipeline.sh берёт flock), карточку писать в файл scratchpad, после отчёта самому проверять `git status`, `zone-check.sh blender`, один кадр, `dev.sh test` (на правку только `.py` он молчит «не затрагивает» — запускать `assets_models_test` явно). Кадры владельцу — `SendUserFile` (он их не видит иначе). Push с Mac: хук берёт JDK 21 — если падает, влить `origin/main` в ветку и повторить; `--no-verify` нельзя. Язык ответов — русский, коммиты русские с `Co-Authored-By`.

**Why:** владелец очищает сессию ради новых правил; нужен быстрый вход без перечитывания 100+ ходов.
**How to apply:** начать с `docs/progress.md`, `git log -10`, статуса PR 87 (`gh pr view 87`), skill netrun-assets; спросить владельца про ждущие решения только если они блокируют работу.
