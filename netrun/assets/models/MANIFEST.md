# Манифест ассетов «Сети»

Собирается `src/validate.py --manifest`, руками не править. Числа взяты из самих `.glb`.
Частота кадров на Pico 4 **не проверена** (нет устройства).

| Файл | Треуг. / бюджет | Точек / бюджет | Слоёв | Вызовов | Размер, м (x, y, z) | Материалы | Анимации | Origin | Статус |
|---|---|---|---|---|---|---|---|---|---|
| `models/env/doorway.glb` | 144 / 300 | 487 / 520 | 2 | 5 | 2.034 × 2.0267 × 0.4613 | points, shell_soft | — | floor | ок |
| `models/env/dust.glb` | 0 / 300 | 625 / 700 | 0 | 2 | 3.0047 × 3.0035 × 2.9936 | points | — | center | ок |
| `models/env/floor.glb` | 12 / 300 | 254 / 320 | 1 | 3 | 2.0348 × 0.0464 × 2.0149 | points, shell_soft | — | floor | ок |
| `models/env/pillar.glb` | 88 / 300 | 218 / 260 | 2 | 4 | 0.3545 × 2.31 × 0.3956 | points, shell_soft | — | floor | ок |
| `models/props/shard.glb` | 60 / 300 | 70 / 120 | 3 | 4 | 0.1303 × 0.1496 × 0.123 | points, shell_soft | — | center | ок |
| `models/ice/soft_ice.glb` | 60 / 3000 | 999 / 1500 | 2 | 5 | 1.0361 × 2.0629 × 0.8515 | points, shell_soft, solid_dark | — | feet | ок |
| `models/env/wall.glb` | 144 / 300 | 599 / 700 | 2 | 4 | 2.024 × 2.0433 × 0.4541 | points, shell_soft | — | floor | ок |
