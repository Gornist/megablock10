// Небо фона-купола как функция направления: свет пустоты по тревоге (спокойный — ноль) и дымка над горизонтом.
// Общая часть backdrop.gdshader (звёзды фона рисуют отдельные мировые частицы, stars.gdshader) и cloud_dark.gdshaderinc (просветы непрозрачной грани
// облака показывают то же небо, что было бы за пустой сценой: грань «прозрачна», но мира за ней нет; владелец 20.10: «чёрный просвет темнее дымки неба, получается силуэт-стена»).
// Все uniform'ы — с префиксом sky_ (в облаке уже есть dust_color и др.); значения ставит AssetMaterials.sky_params / BackdropDome.set_alarm.

uniform vec3 sky_floor : source_color = vec3(0.02, 0.024, 0.03);       // фон вида (Environment.background_color клиента, world_scene.CALM_BG): небо вне граней — он + дымка; просвет грани обязан дать тот же цвет, иначе колонна читается чёрным блоком (на очках 20.10: небо (6,6,6), просвет (0,0,0))
uniform vec3 sky_void : source_color = vec3(0.0, 0.0, 0.0);           // свет пустоты по тревоге (BackdropDome.void_for): спокойный — 0
uniform vec3 sky_haze_color : source_color = vec3(0.012, 0.05, 0.062); // дымка у горизонта: тусклая бирюза
uniform float sky_haze_height : hint_range(0.05, 1.0) = 0.16;          // толщина дымки по sin высоты
uniform float sky_haze_below : hint_range(0.0, 2.0) = 0.0;             // ниже горизонта дымки нет: пол уходит в чёрное
uniform float sky_haze_gain : hint_range(0.0, 3.0) = 1.0;              // ручка `backdrop_haze`

// Дымка по высоте y = d.y (−1…1): ноль выше толщины, максимум на горизонте. Без exp/pow: гладкая «колокольная» форма (1 − u²)² на u = |y| / (2·sky_haze_height).
float sky_haze(float y) {
	float u = clamp(abs(y) / (2.0 * sky_haze_height), 0.0, 1.0);
	float k = 1.0 - u * u;
	return k * k * (y < 0.0 ? sky_haze_below : 0.6);
}

// Небо в направлении d (мировое, единичное): свет пустоты + дымка.
vec3 backdrop_sky(vec3 d) {
	return sky_void + sky_haze_color * sky_haze(d.y) * sky_haze_gain;
}
