# Манифест ассетов «Сети»

Собирается `src/validate.py --manifest`, руками не править. Числа взяты из самих `.glb`.
Частота кадров на Pico 4 **не проверена** (нет устройства).

| Файл | Треуг. / бюджет | Точек / бюджет | Слоёв | Вызовов | Размер, м (x, y, z) | Материалы | Анимации | Origin | Статус |
|---|---|---|---|---|---|---|---|---|---|
| `models/env/dust.glb` | 192 / 300 | 600 / 600 | 0 | 2 | 3.0047 × 3.0041 × 3.0403 | glow_edge, points | — | center | ок |
| `models/props/shard.glb` | 60 / 300 | 70 / 120 | 3 | 4 | 0.1303 × 0.1496 × 0.123 | points, shell_soft | — | center | ок |
| `models/ice/soft_ice.glb` | 88 / 3000 | 1080 / 1500 | 2 | 5 | 1.0361 × 2.0603 × 0.8548 | glow_edge, points, shell_soft, solid_dark | — | feet | ок |
| `models/env/wall.glb` | 228 / 300 | 212 / 400 | 2 | 5 | 2.073 × 2 × 0.6462 | glow_edge, points, shell_soft | — | floor | ок |
