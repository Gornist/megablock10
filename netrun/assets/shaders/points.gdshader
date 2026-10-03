// Облако точек: каждая точка — квадрат из 4 вершин, всегда обращённый к камере, круглая мягкая точка.
// Контракт с lib.py (Blender): квадрат лежит в плоскости XZ Blender (в Godot — XY) с центром c и полуразмером h;
// UV0 — углы квадрата, UV1.x = h. Центр восстанавливаем вычитанием смещения угла из позиции вершины.
// Мерцание медленное и неглубокое (комфорт в VR); цвет и яркость — из цвета вершин.
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, fog_disabled;

uniform float glow : hint_range(0.0, 6.0) = 1.4;
uniform float twinkle : hint_range(0.0, 0.5) = 0.15;
uniform float twinkle_speed : hint_range(0.0, 3.0) = 0.6;
uniform vec4 tint : source_color = vec4(1.0);
uniform float tint_amount : hint_range(0.0, 1.0) = 0.0;

// Corruption: красный «шрам» в радиусе от точки (мировые координаты): цвет уходит в corrupt_color, часть клеток пропадает.
// Дискретные клетки по сетке, без анимации: комфорт в VR (никаких вспышек). Выключено при corrupt_radius = 0.
uniform vec3 corrupt_pos = vec3(0.0);
uniform float corrupt_radius = 0.0;
uniform vec4 corrupt_color : source_color = vec4(1.0, 0.12, 0.24, 1.0);
// Затухание по расстоянию до камеры (замена depth-fade: буфер глубины не читаем, на мобильном дорого).
uniform float fade_start = 60.0;
uniform float fade_end = 90.0;

varying vec3 v_wp;
varying float v_dist;

float corrupt_k() {
	return corrupt_radius > 0.0 ? 1.0 - smoothstep(corrupt_radius * 0.12, corrupt_radius, distance(v_wp, corrupt_pos)) : 0.0;
}
float cell_hash(float salt) {
	return fract(sin(dot(floor(v_wp * 9.0) + salt, vec3(12.9, 78.2, 37.7))) * 43758.5);
}
// Порча по клеткам: клетка либо цвета ассета, либо corrupt_color (вероятность растёт к центру), без серого посередине.
float corrupt_mask(float k) {
	return step(cell_hash(0.0), k);
}
float corrupt_hole(float m) {
	return 1.0 - m * step(cell_hash(7.0), 0.4); // часть порченых клеток пропадает
}
float dist_fade() {
	return 1.0 - smoothstep(fade_start, fade_end, v_dist);
}

varying float v_phase;

void vertex() {
	float h = UV2.x;
	vec3 c = VERTEX - vec3((UV.x - 0.5) * 2.0 * h, (0.5 - UV.y) * 2.0 * h, 0.0);
	v_phase = dot(c, vec3(12.9, 78.2, 37.7));
	v_wp = (MODEL_MATRIX * vec4(c, 1.0)).xyz;
	vec4 mv = MODELVIEW_MATRIX * vec4(c, 1.0);
	v_dist = -mv.z;
	mv.xy += vec2(UV.x - 0.5, 0.5 - UV.y) * 2.0 * h;
	POSITION = PROJECTION_MATRIX * mv;
}

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float soft = smoothstep(1.0, 0.25, d);
	float tw = 1.0 - twinkle + twinkle * sin(TIME * twinkle_speed + v_phase);
	float k = corrupt_k();
	ALBEDO = mix(mix(COLOR.rgb, tint.rgb, tint_amount), corrupt_color.rgb, corrupt_mask(k)) * glow;
	ALPHA = soft * COLOR.a * tw * dist_fade();
}
