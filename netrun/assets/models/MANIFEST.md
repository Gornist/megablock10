# Манифест ассетов «Сети»

Собирается `src/validate.py --manifest`, руками не править. Числа взяты из самих `.glb`.
Частота кадров на Pico 4 **не проверена** (нет устройства).

| Файл | Треуг. / бюджет | Точек / бюджет | Штрихов / бюджет | Слоёв | Вызовов | Размер, м (x, y, z) | Материалы | Анимации | Origin | Статус |
|---|---|---|---|---|---|---|---|---|---|---|
| `models/ice/black_ice.glb` | 0 / 300 | 157 / 600 | 256 / 350 | 0 | 3 | 1.4096 × 3.3711 × 1.68 | points, streaks | idle, hunt, catch | feet | ок |
| `models/ice/black_ice_catch.glb` | 0 / 300 | 156 / 600 | 331 / 350 | 0 | 3 | 2.3818 × 3.3707 × 2.7782 | points, streaks | — | feet | ок |
| `models/ice/black_ice_hunt.glb` | 0 / 300 | 162 / 600 | 282 / 350 | 0 | 3 | 1.3545 × 3.2935 × 2.1668 | points, streaks | — | feet | ок |
| `models/env/cable_curve.glb` | 0 / 300 | 354 / 420 | 0 / 0 | 0 | 2 | 1.9817 × 0.2306 × 1.9636 | points | — | floor | ок |
| `models/env/cable_straight.glb` | 0 / 300 | 354 / 420 | 0 / 0 | 0 | 2 | 1.952 × 0.2306 × 1.9827 | points | — | floor | ок |
| `models/env/ceiling.glb` | 144 / 300 | 37 / 170 | 144 / 200 | 1 | 4 | 1.782 × 0.95 × 1.75 | points, shell_soft, solid_dark, streaks | — | ceiling | ок |
| `models/env/ceiling_b.glb` | 108 / 300 | 34 / 170 | 123 / 200 | 1 | 4 | 1.782 × 0.9499 × 1.75 | points, shell_soft, solid_dark, streaks | — | ceiling | ок |
| `models/env/ceiling_c.glb` | 36 / 300 | 43 / 170 | 67 / 200 | 1 | 4 | 1.782 × 0.8583 × 1.75 | points, shell_soft, solid_dark, streaks | — | ceiling | ок |
| `models/env/column_field.glb` | 0 / 300 | 0 / 0 | 1345 / 1700 | 0 | 1 | 3.9398 × 2.8539 × 3.9 | streaks | — | floor | ок |
| `models/env/corner.glb` | 0 / 300 | 4 / 40 | 167 / 240 | 0 | 3 | 2.0312 × 2.8919 × 1.9991 | points, streaks | — | floor | ок |
| `models/deck/daemon_BLACKOUT.glb` | 80 / 300 | 72 / 140 | 0 / 8 | 0 | 2 | 0.0579 × 0.036 × 0.0512 | points, solid_dark | — | center | ок |
| `models/deck/daemon_DECRYPT.glb` | 88 / 300 | 24 / 140 | 0 / 8 | 2 | 3 | 0.0292 × 0.0292 × 0.0291 | points, shell_soft | — | center | ок |
| `models/deck/daemon_EXTRACT_DAEMON.glb` | 60 / 300 | 56 / 140 | 0 / 8 | 3 | 4 | 0.0472 × 0.0474 × 0.0449 | points, shell_soft | — | center | ок |
| `models/deck/daemon_EXTRACT_SHARD.glb` | 60 / 300 | 20 / 140 | 0 / 8 | 3 | 4 | 0.0219 × 0.0408 × 0.0203 | points, shell_soft | — | center | ок |
| `models/deck/daemon_GHOST.glb` | 40 / 300 | 46 / 140 | 0 / 8 | 2 | 3 | 0.0543 × 0.0846 × 0.0544 | points, shell_soft | — | center | ок |
| `models/deck/daemon_JITTER.glb` | 0 / 300 | 54 / 140 | 0 / 8 | 0 | 2 | 0.0436 × 0.0235 × 0.006 | points | — | center | ок |
| `models/deck/daemon_MINER.glb` | 48 / 300 | 14 / 140 | 0 / 8 | 0 | 2 | 0.034 × 0.0391 × 0.034 | points, solid_dark | — | center | ок |
| `models/deck/daemon_TIMESKEW.glb` | 176 / 300 | 14 / 140 | 0 / 8 | 2 | 3 | 0.0358 × 0.0448 × 0.0358 | points, shell_soft | — | center | ок |
| `models/props/daemon_token.glb` | 84 / 200 | 66 / 80 | 0 / 0 | 2 | 5 | 0.138 × 0.1209 × 0.0153 | points, shell_soft, solid_dark | — | center | ок |
| `models/props/dead_deck.glb` | 68 / 300 | 9 / 20 | 2 / 4 | 0 | 3 | 0.18 × 0.065 × 0.11 | points, solid_dark, streaks | — | center | ок |
| `models/env/doorway.glb` | 0 / 300 | 18 / 40 | 46 / 80 | 0 | 3 | 1.9678 × 2.6921 × 0.1873 | points, streaks | — | floor | ок |
| `models/env/doorway_b.glb` | 0 / 300 | 18 / 40 | 50 / 80 | 0 | 3 | 1.9513 × 2.6668 × 0.2822 | points, streaks | — | floor | ок |
| `models/env/far_ceiling.glb` | 936 / 1100 | 117 / 700 | 247 / 260 | 1 | 4 | 10.84 × 2.9737 × 10.8 | points, shell_soft, solid_dark, streaks | — | ceiling | ок |
| `models/env/far_ceiling_b.glb` | 648 / 1100 | 123 / 700 | 229 / 260 | 1 | 4 | 10.84 × 2.9605 × 10.8 | points, shell_soft, solid_dark, streaks | — | ceiling | ок |
| `models/env/far_ceiling_c.glb` | 468 / 1100 | 118 / 700 | 234 / 260 | 1 | 4 | 10.84 × 2.9751 × 10.8 | points, shell_soft, solid_dark, streaks | — | ceiling | ок |
| `models/env/far_field.glb` | 0 / 100 | 114 / 140 | 91 / 320 | 0 | 2 | 10.76 × 3.5104 × 10.7 | points, streaks | — | floor | ок |
| `models/env/far_field_b.glb` | 0 / 100 | 114 / 140 | 67 / 320 | 0 | 2 | 10.76 × 3.4001 × 10.7 | points, streaks | — | floor | ок |
| `models/env/far_field_c.glb` | 0 / 100 | 114 / 140 | 63 / 320 | 0 | 2 | 10.76 × 3.4686 × 10.7 | points, streaks | — | floor | ок |
| `models/env/far_floor.glb` | 684 / 1100 | 129 / 700 | 236 / 260 | 1 | 4 | 10.84 × 2.9774 × 10.8 | points, shell_soft, solid_dark, streaks | — | surface | ок |
| `models/env/far_floor_b.glb` | 864 / 1100 | 123 / 700 | 232 / 260 | 1 | 4 | 10.84 × 2.9747 × 10.8 | points, shell_soft, solid_dark, streaks | — | surface | ок |
| `models/env/far_floor_c.glb` | 720 / 1100 | 114 / 700 | 233 / 260 | 1 | 4 | 10.84 × 2.9762 × 10.8 | points, shell_soft, solid_dark, streaks | — | surface | ок |
| `models/env/floor.glb` | 252 / 450 | 26 / 170 | 177 / 200 | 1 | 4 | 1.782 × 0.95 × 1.75 | points, shell_soft, solid_dark, streaks | — | surface | ок |
| `models/env/floor_b.glb` | 180 / 450 | 27 / 170 | 181 / 200 | 1 | 4 | 1.782 × 0.95 × 1.75 | points, shell_soft, solid_dark, streaks | — | surface | ок |
| `models/env/floor_c.glb` | 216 / 450 | 26 / 170 | 180 / 200 | 1 | 4 | 1.782 × 0.95 × 1.75 | points, shell_soft, solid_dark, streaks | — | surface | ок |
| `models/env/floor_clear.glb` | 0 / 300 | 58 / 170 | 0 / 200 | 0 | 1 | 1.782 × 0.1032 × 1.75 | points | — | surface | ок |
| `models/env/floor_glass_16.glb` | 66 / 400 | 638 / 700 | 226 / 260 | 2 | 4 | 16.0336 × 0.9227 × 16 | points, shell_soft, streaks | — | slab | ок |
| `models/env/floor_glass_8.glb` | 34 / 200 | 131 / 350 | 112 / 130 | 2 | 4 | 8.0331 × 0.9411 × 8 | points, shell_soft, streaks | — | slab | ок |
| `models/env/floor_slab_16.glb` | 92 / 400 | 638 / 700 | 226 / 260 | 1 | 4 | 16.0336 × 0.9227 × 16 | points, shell_soft, solid_dark, streaks | — | slab | ок |
| `models/env/floor_slab_8.glb` | 60 / 200 | 131 / 350 | 112 / 130 | 1 | 4 | 8.0331 × 0.9411 × 8 | points, shell_soft, solid_dark, streaks | — | slab | ок |
| `models/env/floor_v1_16.glb` | 2 / 600 | 0 / 0 | 875 / 900 | 1 | 2 | 16 × 0.3594 × 16 | shell_soft, streaks | — | floorv | ок |
| `models/env/floor_v1_8.glb` | 2 / 150 | 0 / 0 | 225 / 225 | 1 | 2 | 8 × 0.3531 × 8 | shell_soft, streaks | — | floorv | ок |
| `models/env/floor_v2_16.glb` | 372 / 600 | 0 / 0 | 377 / 600 | 1 | 3 | 16 × 0.94 × 16 | shell_soft, solid_dark, streaks | — | floorv | ок |
| `models/env/floor_v2_8.glb` | 80 / 150 | 0 / 0 | 68 / 150 | 1 | 3 | 8 × 0.8417 × 8 | shell_soft, solid_dark, streaks | — | floorv | ок |
| `models/env/floor_v3_16.glb` | 66 / 600 | 0 / 0 | 181 / 600 | 2 | 3 | 16.0335 × 0.7799 × 16 | shell_soft, streaks | — | floorv | ок |
| `models/env/floor_v3_8.glb` | 34 / 150 | 0 / 0 | 93 / 150 | 2 | 3 | 8.0336 × 0.78 × 8 | shell_soft, streaks | — | floorv | ок |
| `models/env/floor_v4_16.glb` | 576 / 600 | 0 / 0 | 600 / 600 | 0 | 2 | 16 × 0.49 × 15.9084 | solid_dark, streaks | — | floorv | ок |
| `models/env/floor_v4_8.glb` | 150 / 150 | 0 / 0 | 150 / 150 | 0 | 2 | 8 × 0.49 × 8 | solid_dark, streaks | — | floorv | ок |
| `models/props/hack_pad.glb` | 36 / 120 | 128 / 160 | 29 / 40 | 1 | 5 | 0.9259 × 0.28 × 0.9 | points, shell_soft, solid_dark, streaks | — | floor | ок |
| `models/props/hack_panel.glb` | 62 / 300 | 50 / 120 | 11 / 20 | 0 | 5 | 0.5175 × 1.2986 × 0.34 | points, solid_dark, streaks | — | floor | ок |
| `models/env/horizon_band.glb` | 192 / 1000 | 0 / 0 | 360 / 400 | 1 | 2 | 132.9202 × 12 × 122.7654 | shell_soft, streaks | — | horizon | ок |
| `models/env/lockdown_gate.glb` | 0 / 300 | 18 / 40 | 79 / 120 | 0 | 4 | 1.98 × 2.7226 × 0.328 | points, streaks | — | floor | ок |
| `models/env/lockdown_gate_open.glb` | 0 / 300 | 18 / 40 | 48 / 120 | 0 | 4 | 1.98 × 2.7226 × 0.328 | points, streaks | — | floor | ок |
| `models/env/pillar.glb` | 0 / 300 | 0 / 0 | 11 / 16 | 0 | 2 | 0.1166 × 3 × 0.0709 | streaks | — | floor | ок |
| `models/env/platform.glb` | 28 / 300 | 25 / 40 | 39 / 60 | 0 | 3 | 1.9203 × 0.322 × 1.9 | points, solid_dark, streaks | — | floor | ок |
| `models/props/portal.glb` | 0 / 2000 | 358 / 400 | 82 / 100 | 0 | 2 | 3.028 × 3.014 × 0.1571 | points, streaks | — | floor | ок |
| `models/props/portal_locked.glb` | 0 / 2000 | 157 / 260 | 27 / 40 | 0 | 2 | 3.0273 × 3.0139 × 0.1508 | points, streaks | — | floor | ок |
| `models/env/portal_wall.glb` | 0 / 300 | 34 / 150 | 105 / 300 | 0 | 2 | 3.9653 × 2.9735 × 0.5252 | points, streaks | — | floor | ок |
| `models/env/room_edge_16.glb` | 192 / 200 | 0 / 0 | 452 / 500 | 1 | 2 | 19.6 × 3.0135 × 19.6 | shell_soft, streaks | — | edge | ок |
| `models/env/room_edge_8.glb` | 192 / 200 | 0 / 0 | 231 / 260 | 1 | 2 | 11.6 × 2.9844 × 11.6 | shell_soft, streaks | — | edge | ок |
| `models/env/room_moat_16.glb` | 16 / 60 | 0 / 0 | 0 / 0 | 0 | 1 | 22.7 × 0.0 × 22.7 | solid_dark | — | moat | ок |
| `models/env/room_moat_8.glb` | 16 / 60 | 0 / 0 | 0 / 0 | 0 | 1 | 14.7 × 0.0 × 14.7 | solid_dark | — | moat | ок |
| `models/avatar/runner.glb` | 0 / 300 | 140 / 160 | 318 / 360 | 0 | 2 | 0.6575 × 1.4629 × 0.6566 | points, streaks | — | feet | ок |
| `models/avatar/runner_b.glb` | 0 / 300 | 140 / 160 | 318 / 360 | 0 | 2 | 0.5891 × 1.4687 × 0.6358 | points, streaks | — | feet | ок |
| `models/avatar/runner_c.glb` | 0 / 300 | 140 / 160 | 318 / 360 | 0 | 2 | 0.6494 × 1.4711 × 0.6036 | points, streaks | — | feet | ок |
| `models/props/seat.glb` | 252 / 300 | 24 / 40 | 11 / 16 | 0 | 3 | 1.2 × 1.1082 × 1.2 | points, solid_dark, streaks | — | floor | ок |
| `models/props/sensor.glb` | 88 / 500 | 16 / 40 | 2 / 8 | 3 | 6 | 0.342 × 1.45 × 0.32 | points, shell_soft, solid_dark, streaks | — | floor | ок |
| `models/props/shard.glb` | 52 / 300 | 126 / 160 | 0 / 0 | 3 | 7 | 0.1399 × 0.13 × 0.136 | points, shell_soft | — | center | ок |
| `models/props/shard_encrypted.glb` | 12 / 400 | 151 / 220 | 4 / 8 | 1 | 7 | 0.197 × 0.1431 × 0.136 | points, shell_soft, streaks | — | center | ок |
| `models/ice/soft_ice.glb` | 0 / 300 | 160 / 200 | 179 / 200 | 0 | 3 | 1.2214 × 2.15 × 0.7577 | points, streaks | idle, patrol | feet | ок |
| `models/env/tunnel_ring.glb` | 0 / 300 | 188 / 320 | 78 / 120 | 0 | 2 | 3.026 × 3.016 × 1.96 | points, streaks | — | floor | ок |
| `models/props/vault.glb` | 208 / 900 | 300 / 500 | 98 / 220 | 2 | 17 | 0.8064 × 0.807 × 0.7476 | points, shell_soft, solid_dark, streaks | — | floor | ок |
| `models/props/vault_closed.glb` | 0 / 500 | 248 / 420 | 111 / 160 | 0 | 2 | 0.7878 × 0.8098 × 0.76 | points, streaks | — | floor | ок |
| `models/props/vault_open.glb` | 0 / 500 | 248 / 420 | 105 / 160 | 0 | 2 | 0.7878 × 0.9982 × 0.76 | points, streaks | — | floor | ок |
| `models/env/wall.glb` | 0 / 300 | 50 / 80 | 80 / 120 | 0 | 3 | 2.004 × 2.9716 × 0.5351 | points, streaks | — | floor | ок |
| `models/env/wall_b.glb` | 0 / 300 | 50 / 80 | 85 / 120 | 0 | 3 | 2.004 × 2.9653 × 0.4939 | points, streaks | — | floor | ок |
| `models/env/wall_c.glb` | 0 / 300 | 50 / 80 | 82 / 120 | 0 | 3 | 2.004 × 2.9582 × 0.5135 | points, streaks | — | floor | ок |
| `models/deck/wrist_deck.glb` | 80 / 2000 | 184 / 200 | 2 / 8 | 0 | 7 | 0.1085 × 0.0919 × 0.06 | points, solid_dark, streaks | — | center | ок |
