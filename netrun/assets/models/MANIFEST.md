# Манифест ассетов «Сети»

Собирается `src/validate.py --manifest`, руками не править. Числа взяты из самих `.glb`.
Частота кадров на Pico 4 **не проверена** (нет устройства).

| Файл | Треуг. / бюджет | Точек / бюджет | Слоёв | Вызовов | Размер, м (x, y, z) | Материалы | Анимации | Origin | Статус |
|---|---|---|---|---|---|---|---|---|---|
| `models/env/doorway.glb` | 216 / 300 | 160 / 240 | 2 | 5 | 2.014 × 2.0267 × 0.4738 | glow_edge, points, shell_soft | — | floor | ок |
| `models/env/dust.glb` | 192 / 300 | 600 / 600 | 0 | 2 | 3.0047 × 3.0041 × 3.0403 | glow_edge, points | — | center | ок |
| `models/env/floor.glb` | 60 / 300 | 90 / 120 | 1 | 3 | 1.99 × 0.018 × 1.99 | glow_edge, points, shell_soft | — | floor | ок |
| `models/env/pillar.glb` | 112 / 300 | 70 / 120 | 2 | 5 | 0.3969 × 2.34 × 0.397 | glow_edge, points, shell_soft | — | floor | ок |
| `models/props/shard.glb` | 60 / 300 | 70 / 120 | 3 | 4 | 0.1303 × 0.1496 × 0.123 | points, shell_soft | — | center | ок |
| `models/ice/soft_ice.glb` | 88 / 3000 | 1080 / 1500 | 2 | 5 | 1.0361 × 2.0603 × 0.8548 | glow_edge, points, shell_soft, solid_dark | — | feet | ок |
| `models/env/wall.glb` | 264 / 300 | 266 / 400 | 2 | 5 | 2.007 × 2.0433 × 0.4552 | glow_edge, points, shell_soft | — | floor | ок |
