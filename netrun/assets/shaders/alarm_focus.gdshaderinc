// Тревога у игрока (П6-6 (б), ice.md §8 «Правило П6»): на уровне 2+ свет кромок, сетки пола и облака в радиусе вокруг игрока уходит в тревожный цвет, не только фон и общий сдвиг.
// Владелец на П6 не заметил смены цвета при тревоге: фон слабый, а смотрят под ноги и на кромки рядом. Включают solid_dark, cloud_dark и skirt (окружение; существа и аватары не трогаем).
// focus_radius = 0 — выключено (умолчание). Позицию и радиус каждый кадр ставит AssetMaterials.set_alarm_focus.
// Чёрное остаётся чёрным: перекрашивается только свет (яркость берём по максимуму каналов), без серого посередине — переход по радиусу идёт по одному цвету.

uniform vec3 focus_pos = vec3(0.0);
uniform float focus_radius : hint_range(0.0, 20.0) = 0.0;
uniform vec4 focus_color : source_color = vec4(1.0, 0.48, 0.42, 1.0);
uniform float focus_gain : hint_range(0.0, 3.0) = 1.0;   // усиление света в центре: тёплый свет по восприятию тусклее голубого

vec3 focus_light(vec3 glow, vec3 wp) {
	if (focus_radius <= 0.0) {
		return glow;
	}
	float k = 1.0 - smoothstep(focus_radius * 0.25, focus_radius, distance(wp, focus_pos));
	float l = max(glow.r, max(glow.g, glow.b));
	return mix(glow, focus_color.rgb * l * focus_gain, k);
}
