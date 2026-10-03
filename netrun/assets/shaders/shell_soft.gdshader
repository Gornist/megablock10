// Мягкая оболочка: аддитивная, без освещения, ярче у силуэта (Френель), почти прозрачная в центре.
// Аддитив не зависит от порядка рисования; глубину не пишем. Цвет и плотность — из цвета вершин (RGB, A).
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_back, fog_disabled;

uniform float glow : hint_range(0.0, 4.0) = 1.2;
uniform float fresnel_power : hint_range(0.5, 6.0) = 2.5;
uniform float center_alpha : hint_range(0.0, 1.0) = 0.15;
uniform vec4 tint : source_color = vec4(1.0);
uniform float tint_amount : hint_range(0.0, 1.0) = 0.0; // тир: 1.0 перекрашивает в tint

void fragment() {
	float f = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), fresnel_power);
	vec3 base = mix(COLOR.rgb, tint.rgb, tint_amount);
	ALBEDO = base * glow;
	ALPHA = COLOR.a * mix(center_alpha, 1.0, f);
}
