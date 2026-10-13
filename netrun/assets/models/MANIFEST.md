# Манифест ассетов «Сети»

Собирается `src/validate.py --manifest`, руками не править. Числа взяты из самих `.glb`.
Частота кадров на Pico 4 **не проверена** (нет устройства).

| Файл | Треуг. / бюджет | Точек / бюджет | Штрихов / бюджет | Слоёв | Вызовов | Размер, м (x, y, z) | Материалы | Анимации | Origin | Статус |
|---|---|---|---|---|---|---|---|---|---|---|
| `models/ice/black_ice.glb` | 0 / 300 | 157 / 600 | 256 / 350 | 0 | 3 | 1.4096 × 3.3711 × 1.68 | points, streaks | idle, hunt, catch | feet | ок |
| `models/ice/black_ice_catch.glb` | 0 / 300 | 156 / 600 | 331 / 350 | 0 | 3 | 2.3818 × 3.3707 × 2.7782 | points, streaks | — | feet | ок |
| `models/ice/black_ice_hunt.glb` | 0 / 300 | 162 / 600 | 282 / 350 | 0 | 3 | 1.3545 × 3.2935 × 2.1668 | points, streaks | — | feet | ок |
| `models/env/ceiling.glb` | 144 / 300 | 0 / 0 | 0 / 0 | 1 | 2 | 1.5252 × 0.8115 × 1.4557 | shell_soft, solid_dark | — | ceiling | ок |
| `models/env/ceiling_b.glb` | 108 / 300 | 0 / 0 | 0 / 0 | 1 | 2 | 1.1653 × 0.7915 × 1.5791 | shell_soft, solid_dark | — | ceiling | ок |
| `models/env/ceiling_c.glb` | 36 / 300 | 0 / 0 | 0 / 0 | 1 | 2 | 1.1463 × 0.728 × 0.7571 | shell_soft, solid_dark | — | ceiling | ок |
| `models/env/cover.glb` | 116 / 140 | 0 / 0 | 0 / 0 | 0 | 2 | 1.0 × 2.2 × 1.0 | solid_dark | — | floor | ок |
| `models/deck/daemon_BLACKOUT.glb` | 80 / 300 | 72 / 140 | 0 / 8 | 0 | 2 | 0.0579 × 0.036 × 0.0512 | points, solid_dark | — | center | ок |
| `models/deck/daemon_DECRYPT.glb` | 88 / 300 | 24 / 140 | 0 / 8 | 2 | 3 | 0.0292 × 0.0292 × 0.0291 | points, shell_soft | — | center | ок |
| `models/deck/daemon_EXTRACT_DAEMON.glb` | 60 / 300 | 56 / 140 | 0 / 8 | 3 | 4 | 0.0472 × 0.0474 × 0.0449 | points, shell_soft | — | center | ок |
| `models/deck/daemon_EXTRACT_SHARD.glb` | 60 / 300 | 20 / 140 | 0 / 8 | 3 | 4 | 0.0219 × 0.0408 × 0.0203 | points, shell_soft | — | center | ок |
| `models/deck/daemon_GHOST.glb` | 40 / 300 | 46 / 140 | 0 / 8 | 2 | 3 | 0.0543 × 0.0846 × 0.0544 | points, shell_soft | — | center | ок |
| `models/deck/daemon_JITTER.glb` | 0 / 300 | 54 / 140 | 0 / 8 | 0 | 2 | 0.0436 × 0.0235 × 0.006 | points | — | center | ок |
| `models/deck/daemon_MINER.glb` | 48 / 300 | 14 / 140 | 0 / 8 | 0 | 2 | 0.034 × 0.0391 × 0.034 | points, solid_dark | — | center | ок |
| `models/deck/daemon_TIMESKEW.glb` | 176 / 300 | 14 / 140 | 0 / 8 | 2 | 3 | 0.0358 × 0.0448 × 0.0358 | points, shell_soft | — | center | ок |
| `models/props/daemon_token.glb` | 86 / 200 | 66 / 80 | 3 / 3 | 3 | 7 | 0.138 × 0.1209 × 0.0153 | points, shell_soft, solid_dark, streaks | — | center | ок |
| `models/props/dead_deck.glb` | 68 / 300 | 9 / 20 | 2 / 4 | 0 | 3 | 0.18 × 0.065 × 0.11 | points, solid_dark, streaks | — | center | ок |
| `models/env/exit_frame.glb` | 352 / 450 | 18 / 60 | 29 / 140 | 0 | 7 | 1.9627 × 2.2792 × 0.1789 | points, solid_dark, streaks | — | floor | ок |
| `models/env/far_ceiling.glb` | 832 / 1100 | 0 / 0 | 0 / 0 | 1 | 2 | 10.2229 × 2.9758 × 9.9755 | shell_soft, solid_dark | — | ceiling | ок |
| `models/env/far_ceiling_b.glb` | 576 / 1100 | 0 / 0 | 0 / 0 | 1 | 2 | 9.7011 × 2.9387 × 10.2645 | shell_soft, solid_dark | — | ceiling | ок |
| `models/env/far_ceiling_c.glb` | 416 / 1100 | 0 / 0 | 0 / 0 | 1 | 2 | 9.7476 × 2.96 × 9.0408 | shell_soft, solid_dark | — | ceiling | ок |
| `models/env/far_floor.glb` | 684 / 1100 | 0 / 0 | 0 / 0 | 1 | 2 | 9.9339 × 3.9349 × 9.4 | shell_soft, solid_dark | — | surface | ок |
| `models/env/far_floor_b.glb` | 864 / 1100 | 0 / 0 | 0 / 0 | 1 | 2 | 9.6717 × 3.9201 × 10.0736 | shell_soft, solid_dark | — | surface | ок |
| `models/env/far_floor_c.glb` | 720 / 1100 | 0 / 0 | 0 / 0 | 1 | 2 | 10.1618 × 3.944 × 9.8894 | shell_soft, solid_dark | — | surface | ок |
| `models/env/floor.glb` | 308 / 450 | 0 / 0 | 0 / 0 | 1 | 2 | 1.5512 × 1.3933 × 1.5796 | shell_soft, solid_dark | — | surface | ок |
| `models/env/floor_b.glb` | 220 / 450 | 0 / 0 | 0 / 0 | 1 | 2 | 1.5527 × 1.3397 × 1.5975 | shell_soft, solid_dark | — | surface | ок |
| `models/env/floor_c.glb` | 264 / 450 | 0 / 0 | 0 / 0 | 1 | 2 | 1.5875 × 1.3682 × 1.5445 | shell_soft, solid_dark | — | surface | ок |
| `models/env/floor_slab_16.glb` | 92 / 400 | 0 / 0 | 0 / 0 | 1 | 2 | 16 × 0.7787 × 16 | shell_soft, solid_dark | — | slab | ок |
| `models/props/hack_pad.glb` | 36 / 120 | 128 / 160 | 29 / 40 | 1 | 5 | 0.9259 × 0.28 × 0.9 | points, shell_soft, solid_dark, streaks | — | floor | ок |
| `models/props/hack_panel.glb` | 62 / 300 | 50 / 120 | 11 / 20 | 0 | 5 | 0.5175 × 1.2986 × 0.34 | points, solid_dark, streaks | — | floor | ок |
| `models/env/lockdown_gate.glb` | 300 / 320 | 0 / 0 | 0 / 0 | 0 | 1 | 0.89 × 2 × 0.09 | solid_dark | — | floor | ок |
| `models/env/lockdown_gate_open.glb` | 300 / 320 | 0 / 0 | 0 / 0 | 0 | 1 | 0.89 × 0.12 × 0.09 | solid_dark | — | floor | ок |
| `models/env/pillar.glb` | 464 / 560 | 0 / 0 | 0 / 0 | 0 | 2 | 2 × 2.2 × 2 | solid_dark | — | floor | ок |
| `models/env/platform.glb` | 28 / 300 | 25 / 40 | 39 / 60 | 0 | 3 | 1.9203 × 0.322 × 1.9 | points, solid_dark, streaks | — | floor | ок |
| `models/props/portal.glb` | 0 / 2000 | 358 / 400 | 82 / 100 | 0 | 2 | 3.028 × 3.014 × 0.1571 | points, streaks | — | floor | ок |
| `models/props/portal_locked.glb` | 0 / 2000 | 157 / 260 | 27 / 40 | 0 | 2 | 3.0273 × 3.0139 × 0.1508 | points, streaks | — | floor | ок |
| `models/avatar/runner.glb` | 0 / 300 | 140 / 160 | 318 / 360 | 0 | 2 | 0.6575 × 1.4629 × 0.6566 | points, streaks | — | feet | ок |
| `models/avatar/runner_b.glb` | 0 / 300 | 140 / 160 | 318 / 360 | 0 | 2 | 0.5891 × 1.4687 × 0.6358 | points, streaks | — | feet | ок |
| `models/avatar/runner_c.glb` | 0 / 300 | 140 / 160 | 318 / 360 | 0 | 2 | 0.6494 × 1.4711 × 0.6036 | points, streaks | — | feet | ок |
| `models/props/seat.glb` | 252 / 300 | 24 / 40 | 11 / 16 | 0 | 3 | 1.2 × 1.1082 × 1.2 | points, solid_dark, streaks | — | floor | ок |
| `models/props/sensor.glb` | 88 / 500 | 16 / 40 | 2 / 8 | 3 | 6 | 0.342 × 1.45 × 0.32 | points, shell_soft, solid_dark, streaks | — | floor | ок |
| `models/props/shard.glb` | 54 / 300 | 126 / 160 | 3 / 3 | 4 | 9 | 0.1399 × 0.13 × 0.136 | points, shell_soft, streaks | — | center | ок |
| `models/props/shard_encrypted.glb` | 14 / 400 | 151 / 220 | 7 / 7 | 2 | 9 | 0.197 × 0.1431 × 0.136 | points, shell_soft, streaks | — | center | ок |
| `models/ice/soft_ice.glb` | 0 / 300 | 160 / 200 | 179 / 200 | 0 | 3 | 1.2214 × 2.15 × 0.7577 | points, streaks | idle, patrol | feet | ок |
| `models/props/vault.glb` | 208 / 900 | 314 / 500 | 107 / 220 | 2 | 17 | 0.9277 × 0.807 × 0.9085 | points, shell_soft, solid_dark, streaks | — | floor | ок |
| `models/props/vault_closed.glb` | 0 / 500 | 248 / 420 | 111 / 160 | 0 | 2 | 0.7878 × 0.8098 × 0.76 | points, streaks | — | floor | ок |
| `models/props/vault_open.glb` | 0 / 500 | 248 / 420 | 105 / 160 | 0 | 2 | 0.7878 × 0.9982 × 0.76 | points, streaks | — | floor | ок |
| `models/deck/wrist_deck.glb` | 80 / 2000 | 184 / 200 | 2 / 8 | 0 | 7 | 0.1085 × 0.0919 × 0.06 | points, solid_dark, streaks | — | center | ок |

## Облако частиц (Б): `.points` рядом с моделью

Формат — 7 float32 на точку (28 байт), порядок перемешан (ЛОД = префикс); генератор `src/points.py`.

| Файл | Точек / бюджет | Байт | Статус |
|---|---|---|---|
| `models/props/vault.points` | 1500 / 1500 | 42000 | ок |
| `models/props/portal.points` | 800 / 800 | 22400 | ок |
| `models/props/shard.points` | 300 / 300 | 8400 | ок |
| `models/props/shard_encrypted.points` | 300 / 300 | 8400 | ок |
