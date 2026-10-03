// Тёмная непрозрачная основа (силуэт, закрывает то, что за ней). Свет несёт цвет вершины (альфа до Godot не доходит): чёрный — нет света, цвет — свет, × edge_glow —
// так у тайлов пола и потолка светится тонкий контур верхней грани (рамка 1,4 см), остальное чёрное. Фреснеля больше нет (у чёрных вершин он был нулевой).
shader_type spatial;
render_mode unshaded, cull_back, fog_disabled;

uniform vec4 base_color : source_color = vec4(0.008, 0.016, 0.03, 1.0);
uniform float edge_glow : hint_range(0.0, 4.0) = 0.75;        // общая яркость контура (почти прозрачный: тусклый, фон просвечивает сквозь свет)
uniform float edge_uneven : hint_range(0.0, 1.0) = 0.92;    // неравномерность: 0 — ровная линия, 1 — от почти погасшей до полной яркости
uniform float edge_noise_scale : hint_range(1.0, 40.0) = 14.0; // пятен света на метр вдоль контура
uniform float edge_drift : hint_range(0.0, 1.0) = 0.12;      // медленное «плавание» пятен света, 1/с
uniform vec4 tint : source_color = vec4(1.0);
uniform float tint_amount : hint_range(0.0, 1.0) = 0.0;

// Перекраска тиром сохраняет чёрное и белое: у чёрных вершин (тайлы пола) кайма остаётся нулевой.
vec3 recolor(vec3 c) {
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	return mix(tint.rgb * mx, c, mn / max(mx, 0.0001));
}

varying vec3 v_wp;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}
// Гладкий шум по мировой позиции: у соседних тайлов своё пятно света, у одного ребра свет вдоль него неровный.
float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n = vnoise(v_wp * edge_noise_scale + vec3(TIME * edge_drift, 0.0, TIME * edge_drift * 0.7));
	float lit = mix(1.0, smoothstep(0.38, 0.62, n), edge_uneven);
	ALBEDO = base_color.rgb + mix(COLOR.rgb, recolor(COLOR.rgb), tint_amount) * edge_glow * lit;
}
