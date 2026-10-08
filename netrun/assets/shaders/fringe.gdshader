// Мягкая светящаяся обводка силуэта непрозрачного объёма (укрытия, колонны, хранилище, брусья выхода) — «сглаживание» без MSAA.
// Видимая граница таких объёмов — светящаяся кромка (3 см) на тёмном фоне: бинарная граница пикселя = лесенка («пила»). MSAA 4× даёт вспышки на прозрачных штрихах, 2× — мерцание граней.
// Здесь: обратные грани (cull_front) раздуваются по сглаженной нормали на px пикселей ЭКРАНА и рисуются аддитивно цветом вершин (как кромка) с малой альфой —
// видна только полоса снаружи силуэта (внутри её закрывают передние грани через тест глубины). Два слоя через next_pass (узкий и широкий, слабее) дают три ступени
// яркости на краю вместо двух: ступенька размазана на 1–3 пикселя, как у настоящего покрытия. Цвет и тир — как у solid_dark (COLOR вершин, tint).
// Нужны сглаженные нормали меша (Blender: smooth=True), иначе на рёбрах граней полоса рвётся. Глубину не пишет.
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_front, fog_disabled;

uniform float px : hint_range(0.0, 6.0) = 1.2;               // на сколько пикселей экрана полоса выходит за силуэт
uniform float fringe_alpha : hint_range(0.0, 1.0) = 0.5;     // яркость полосы (доля от яркости кромки)
uniform float edge_glow : hint_range(0.0, 4.0) = 2.2;        // как у solid_dark (AssetMaterials.PILLAR_EDGE)
uniform vec4 tint : source_color = vec4(1.0);
uniform float tint_amount : hint_range(0.0, 1.0) = 0.0;
uniform float edge_soft : hint_range(0.0, 1.0) = 0.0;       // как у solid_dark: свет у самого силуэта гасится, обводка гаснет вместе с ним (edge_soft.gdshaderinc)
#include "edge_soft.gdshaderinc"
uniform float fade_start = 40.0;                              // дальше объём субпиксельный, обводка не нужна
uniform float fade_end = 60.0;

varying float v_fade;

vec3 recolor(vec3 c) {
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	return mix(tint.rgb * mx, c, mn / max(mx, 0.0001));
}

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 nv = normalize(mat3(MODELVIEW_MATRIX) * NORMAL);
	vec2 dir = (PROJECTION_MATRIX * vec4(nv, 0.0)).xy;
	float l = length(dir);
	dir = l > 0.00001 ? dir / l : vec2(0.0);
	vec2 off = dir * px * 2.0 / VIEWPORT_SIZE;   // NDC на пиксель = 2 / размер вьюпорта
	POSITION = vec4(clip.xy + off * clip.w, clip.zw);
	v_fade = 1.0 - smoothstep(fade_start, fade_end, clip.w);
}

void fragment() {
	ALBEDO = mix(COLOR.rgb, recolor(COLOR.rgb), tint_amount) * edge_glow * edge_soft_gain(max(COLOR.r, max(COLOR.g, COLOR.b)), edge_soft);
	ALPHA = fringe_alpha * v_fade;
}
