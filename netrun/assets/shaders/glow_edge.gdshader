// Светящиеся рёбра и контуры: аддитивные, без освещения, без записи глубины. Яркость — из A цвета вершин.
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, fog_disabled;

uniform float glow : hint_range(0.0, 6.0) = 2.0;
uniform vec4 tint : source_color = vec4(1.0);
uniform float tint_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	ALBEDO = mix(COLOR.rgb, tint.rgb, tint_amount) * glow;
	ALPHA = COLOR.a;
}
