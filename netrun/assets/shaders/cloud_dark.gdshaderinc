// Тело «облака без основы» (включает cloud_dark.gdshader; вынесено в .gdshaderinc, чтобы не раздувать шейдер и держать вместе с volume_cloud.gdshaderinc).
// Вес ребра берём из цвета вершины (1 на стыке → 0 на 3 см), линии клеток пола — из той же текстуры grid_tex, что у solid_dark: там плотность поднимается до скопления (линия остаётся читаемой, но из частиц).
// Нормаль и позиция идут varying'ами от вершины (не NORMAL фрагмента), поэтому узор привязан к мировой решётке и не «плывёт» при движении головы.

#include "volume_cloud.gdshaderinc"
#include "breath_touch.gdshaderinc"

uniform sampler2D grid_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float grid_alpha : hint_range(0.0, 2.0) = 0.0;
uniform vec2 grid_origin = vec2(0.0);
uniform vec4 edge_color : source_color = vec4(0.094, 0.9, 1.0, 1.0);
uniform float edge_mix : hint_range(0.0, 1.0) = 0.35;   // насколько частицы ребра краснее к цвету неона (меньше неона — владелец)

varying vec3 v_wp;
varying vec3 v_nw;
varying float v_dist;
varying float v_top;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_nw = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_dist = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
	v_top = NORMAL.y;
}

void fragment() {
	float edge = max(COLOR.r, max(COLOR.g, COLOR.b));
	if (grid_alpha > 0.0 && v_top > 0.9) {
		float g = texture(grid_tex, v_wp.xz - grid_origin).r;
		edge = max(edge, clamp(g * grid_alpha * 3.0, 0.0, 1.0));
	}
	// Дыхание по такту хода и отклик на руку/аватар: плотность и яркость частиц (значения задаёт клиент; умолчания — как раньше).
	float lift = breath_lift(v_wp);
	vec3 push = vec3(0.0);
	float tk = touch_k(v_wp, push);
	float dens_k = max(1.0 + 1.4 * (lift - 1.0) + touch_grow * tk, 0.0);
	vec4 c = volume_cloud(v_wp, normalize(v_nw), normalize(CAMERA_POSITION_WORLD - v_wp), v_dist, PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y, edge, dens_k);
	c.rgb *= lift * (1.0 + touch_gain * tk);
	c.rgb = mix(c.rgb, touch_color * dust, 0.5 * tk);
	ALBEDO = mix(c.rgb, edge_color.rgb, edge * edge_mix);
	ALPHA = c.a;
}
