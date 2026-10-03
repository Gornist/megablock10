// Мягкая оболочка: аддитивная, без освещения, ярче у силуэта (Френель), почти прозрачная в центре.
// Аддитив не зависит от порядка рисования; глубину не пишем. Цвет и плотность — из цвета вершин (RGB, A).
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_back, fog_disabled;

uniform float glow : hint_range(0.0, 4.0) = 0.9;
uniform float fresnel_power : hint_range(0.5, 6.0) = 2.5;
uniform float center_alpha : hint_range(0.0, 1.0) = 0.1;
uniform vec4 tint : source_color = vec4(1.0);
uniform float tint_amount : hint_range(0.0, 1.0) = 0.0; // тир: 1.0 перекрашивает в tint

// Corruption: красный «шрам» в радиусе от точки (мировые координаты): цвет уходит в corrupt_color, часть клеток пропадает.
// Дискретные клетки по сетке, без анимации: комфорт в VR (никаких вспышек). Выключено при corrupt_radius = 0.
uniform vec3 corrupt_pos = vec3(0.0);
uniform float corrupt_radius = 0.0;
uniform vec4 corrupt_color : source_color = vec4(1.0, 0.12, 0.24, 1.0);
// Затухание по расстоянию до камеры (замена depth-fade: буфер глубины не читаем, на мобильном дорого).
uniform float fade_start = 60.0;
uniform float fade_end = 90.0;
uniform float intensity = 1.0; // общий множитель яркости (отражение в полу = 0.2)

varying vec3 v_wp;
varying float v_dist;

float corrupt_k() {
	return corrupt_radius > 0.0 ? 1.0 - smoothstep(corrupt_radius * 0.12, corrupt_radius, distance(v_wp, corrupt_pos)) : 0.0;
}
float cell_hash(float salt) {
	return fract(sin(dot(floor(v_wp * vec3(2.5, 16.0, 2.5)) + salt, vec3(12.9, 78.2, 37.7))) * 43758.5);
}
// Порча горизонтальными полосами (глитч, как в референсе Blackwall): полоса либо цвета ассета, либо corrupt_color, без серого посередине.
float corrupt_mask(float k) {
	return step(cell_hash(0.0), k);
}
float corrupt_hole(float m) {
	return 1.0 - m * step(cell_hash(7.0), 0.4); // часть порченых клеток пропадает
}
// Тир перекрашивает цвет ассета в tint, но белые акценты (проёмы, порог, узлы) остаются белыми: чем ближе цвет к белому, тем меньше перекраска.
vec3 recolor(vec3 c) {
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	return mix(tint.rgb * mx, c, mn / max(mx, 0.0001));
}
float dist_fade() {
	return 1.0 - smoothstep(fade_start, fade_end, v_dist);
}

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_dist = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}

void fragment() {
	float f = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), fresnel_power);
	float k = corrupt_k();
	vec3 base = mix(mix(COLOR.rgb, recolor(COLOR.rgb), tint_amount), corrupt_color.rgb, corrupt_mask(k));
	ALBEDO = base * glow;
	ALPHA = COLOR.a * mix(center_alpha, 1.0, f) * corrupt_hole(corrupt_mask(k)) * dist_fade() * intensity;
}
