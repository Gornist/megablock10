# Манифест ассетов «Сети»

Собирается `src/validate.py --manifest`, руками не править. Числа взяты из самих `.glb`.
Частота кадров на Pico 4 **не проверена** (нет устройства).

| Файл | Треуг. / бюджет | Точек / бюджет | Штрихов / бюджет | Слоёв | Вызовов | Размер, м (x, y, z) | Материалы | Анимации | Origin | Статус |
|---|---|---|---|---|---|---|---|---|---|---|
| `models/env/ceiling.glb` | 60 / 300 | 39 / 170 | 354 / 420 | 0 | 3 | 1.8617 × 0.739 × 1.92 | points, solid_dark, streaks | — | ceiling | ок |
| `models/env/ceiling_b.glb` | 60 / 300 | 41 / 170 | 347 / 420 | 0 | 3 | 1.9403 × 0.8043 × 1.92 | points, solid_dark, streaks | — | ceiling | ок |
| `models/env/ceiling_c.glb` | 60 / 300 | 38 / 170 | 347 / 420 | 0 | 3 | 1.8616 × 0.9476 × 1.92 | points, solid_dark, streaks | — | ceiling | ок |
| `models/env/column_field.glb` | 0 / 300 | 0 / 0 | 1345 / 1700 | 0 | 1 | 3.9398 × 2.8539 × 3.9 | streaks | — | floor | ок |
| `models/env/doorway.glb` | 0 / 300 | 18 / 40 | 46 / 80 | 0 | 3 | 1.9678 × 2.6921 × 0.1873 | points, streaks | — | floor | ок |
| `models/env/doorway_b.glb` | 0 / 300 | 18 / 40 | 50 / 80 | 0 | 3 | 1.9513 × 2.6668 × 0.2822 | points, streaks | — | floor | ок |
| `models/env/far_ceiling.glb` | 408 / 600 | 162 / 700 | 544 / 650 | 0 | 3 | 10.84 × 0.8408 × 10.8 | points, solid_dark, streaks | — | ceiling | ок |
| `models/env/far_ceiling_b.glb` | 408 / 600 | 162 / 700 | 544 / 650 | 0 | 3 | 10.84 × 0.81 × 10.8 | points, solid_dark, streaks | — | ceiling | ок |
| `models/env/far_ceiling_c.glb` | 408 / 600 | 155 / 700 | 544 / 650 | 0 | 3 | 10.84 × 0.8828 × 10.8 | points, solid_dark, streaks | — | ceiling | ок |
| `models/env/far_field.glb` | 0 / 100 | 114 / 140 | 43 / 160 | 0 | 2 | 10.76 × 3.5121 × 10.7 | points, streaks | — | floor | ок |
| `models/env/far_field_b.glb` | 0 / 100 | 114 / 140 | 45 / 160 | 0 | 2 | 10.76 × 3.5276 × 10.7 | points, streaks | — | floor | ок |
| `models/env/far_field_c.glb` | 0 / 100 | 114 / 140 | 29 / 160 | 0 | 2 | 10.76 × 3.4917 × 10.7 | points, streaks | — | floor | ок |
| `models/env/far_floor.glb` | 408 / 600 | 150 / 700 | 544 / 650 | 0 | 3 | 10.84 × 0.8397 × 10.8 | points, solid_dark, streaks | — | surface | ок |
| `models/env/far_floor_b.glb` | 408 / 600 | 163 / 700 | 544 / 650 | 0 | 3 | 10.84 × 0.893 × 10.8 | points, solid_dark, streaks | — | surface | ок |
| `models/env/far_floor_c.glb` | 408 / 600 | 148 / 700 | 544 / 650 | 0 | 3 | 10.84 × 0.8263 × 10.8 | points, solid_dark, streaks | — | surface | ок |
| `models/env/floor.glb` | 60 / 300 | 38 / 170 | 358 / 420 | 0 | 3 | 1.9418 × 0.7152 × 1.835 | points, solid_dark, streaks | — | surface | ок |
| `models/env/floor_b.glb` | 60 / 300 | 37 / 170 | 352 / 420 | 0 | 3 | 1.8612 × 0.95 × 1.92 | points, solid_dark, streaks | — | surface | ок |
| `models/env/floor_c.glb` | 60 / 300 | 40 / 170 | 347 / 420 | 0 | 3 | 1.9411 × 0.7564 × 1.835 | points, solid_dark, streaks | — | surface | ок |
| `models/env/pillar.glb` | 0 / 300 | 0 / 0 | 11 / 16 | 0 | 2 | 0.1166 × 3 × 0.0709 | streaks | — | floor | ок |
| `models/props/portal_closed.glb` | 0 / 2000 | 157 / 260 | 27 / 40 | 0 | 2 | 3.0273 × 3.0139 × 0.1508 | points, streaks | — | floor | ок |
| `models/props/portal_open.glb` | 0 / 2000 | 358 / 400 | 82 / 100 | 0 | 2 | 3.028 × 3.014 × 0.1571 | points, streaks | — | floor | ок |
| `models/env/portal_wall.glb` | 0 / 300 | 34 / 150 | 105 / 300 | 0 | 2 | 3.9653 × 2.9735 × 0.5252 | points, streaks | — | floor | ок |
| `models/avatar/runner.glb` | 0 / 300 | 140 / 160 | 318 / 360 | 0 | 2 | 0.6575 × 1.4629 × 0.6566 | points, streaks | — | feet | ок |
| `models/avatar/runner_b.glb` | 0 / 300 | 140 / 160 | 318 / 360 | 0 | 2 | 0.5891 × 1.4687 × 0.6358 | points, streaks | — | feet | ок |
| `models/avatar/runner_c.glb` | 0 / 300 | 140 / 160 | 318 / 360 | 0 | 2 | 0.6494 × 1.4711 × 0.6036 | points, streaks | — | feet | ок |
| `models/props/shard.glb` | 60 / 300 | 70 / 120 | 0 / 0 | 3 | 4 | 0.1303 × 0.1496 × 0.123 | points, shell_soft | — | center | ок |
| `models/ice/soft_ice.glb` | 0 / 300 | 160 / 200 | 179 / 200 | 0 | 3 | 1.2214 × 2.15 × 0.7577 | points, streaks | — | feet | ок |
| `models/props/vault_closed.glb` | 0 / 500 | 248 / 420 | 111 / 160 | 0 | 2 | 0.7878 × 0.8098 × 0.76 | points, streaks | — | floor | ок |
| `models/props/vault_open.glb` | 0 / 500 | 248 / 420 | 105 / 160 | 0 | 2 | 0.7878 × 0.9982 × 0.76 | points, streaks | — | floor | ок |
| `models/env/wall.glb` | 0 / 300 | 50 / 80 | 80 / 120 | 0 | 3 | 2.004 × 2.9716 × 0.5351 | points, streaks | — | floor | ок |
| `models/env/wall_b.glb` | 0 / 300 | 50 / 80 | 85 / 120 | 0 | 3 | 2.004 × 2.9653 × 0.4939 | points, streaks | — | floor | ок |
| `models/env/wall_c.glb` | 0 / 300 | 50 / 80 | 82 / 120 | 0 | 3 | 2.004 × 2.9582 × 0.5135 | points, streaks | — | floor | ок |
