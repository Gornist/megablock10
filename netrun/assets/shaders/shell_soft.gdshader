// Мягкая оболочка: аддитивная, без освещения, ярче у силуэта (Френель), почти прозрачная в центре.
// Аддитив не зависит от порядка рисования; глубину не пишем. Цвет и плотность — из цвета вершин (RGB, A).
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_back, fog_disabled;

uniform float glow : hint_range(0.0, 4.0) = 0.9;
uniform float fresnel_power : hint_range(0.5, 6.0) = 2.5;
uniform float center_alpha : hint_range(0.0, 1.0) = 0.1;
uniform vec4 tint : source_color = vec4(1.0);
uniform float tint_amount : hint_range(0.0, 1.0) = 0.0; // тир: 1.0 перекрашивает в tint

// Затухание по расстоянию до камеры (замена depth-fade: буфер глубины не читаем, на мобильном дорого).
uniform float fade_start = 60.0;
uniform float fade_end = 90.0;
uniform float intensity = 1.0; // общий множитель яркости (отражение в полу = 0.2)

varying float v_dist;

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
	v_dist = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}

void fragment() {
	float f = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), fresnel_power);
	vec3 base = mix(COLOR.rgb, recolor(COLOR.rgb), tint_amount);
	ALBEDO = base * glow;
	ALPHA = COLOR.a * mix(center_alpha, 1.0, f) * dist_fade() * intensity;
}
