// Цвет пустоты для просветов непрозрачной грани облака (cloud_dark.gdshaderinc). Вид V11 (31.10): неба, купола, звёзд и дымки нет — просвет между частицами
// равен фону клиента (Environment.background_color, world_scene.CALM_BG) плюс сдвиг по тревоге. Имя файла осталось от купола (на него ссылается тест
// backdrop_wiring_test); значения ставит AssetMaterials.set_sky_void / BackdropDome.set_alarm.

uniform vec3 sky_floor : source_color = vec3(0.02, 0.024, 0.03);   // фон вида: world_scene.CALM_BG (тест backdrop_wiring_test держит их равными); V11 — #0A0C0E
uniform vec3 sky_void : source_color = vec3(0.0, 0.0, 0.0);        // сдвиг пустоты по тревоге (BackdropDome.void_for): спокойный — 0
