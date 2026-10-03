// Тёмная непрозрачная основа (силуэт, закрывает то, что за ней) с тонкой подсветкой по краю цветом из вершин.
shader_type spatial;
render_mode unshaded, cull_back, fog_disabled;

uniform vec4 base_color : source_color = vec4(0.008, 0.016, 0.03, 1.0);
uniform float rim : hint_range(0.0, 2.0) = 0.6;
uniform float rim_power : hint_range(0.5, 6.0) = 3.0;
uniform vec4 tint : source_color = vec4(1.0);
uniform float tint_amount : hint_range(0.0, 1.0) = 0.0;

// Перекраска тиром сохраняет чёрное и белое: у чёрных вершин (тайлы пола) кайма остаётся нулевой.
vec3 recolor(vec3 c) {
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	return mix(tint.rgb * mx, c, mn / max(mx, 0.0001));
}

void fragment() {
	float f = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);
	ALBEDO = base_color.rgb + mix(COLOR.rgb, recolor(COLOR.rgb), tint_amount) * rim * f;
}
