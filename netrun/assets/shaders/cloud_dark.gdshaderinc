// Общее тело «облака без основы» (см. cloud_dark.gdshader и cloud_dark_2s.gdshader: у них разные только cull_back / cull_disabled — режим отсечения шейдером не переключить uniform'ом).
// Вес ребра берём из цвета вершины (1 на стыке → 0 на 3 см), линии клеток пола — из той же текстуры grid_tex, что у solid_dark: там плотность поднимается до скопления (линия остаётся читаемой, но из частиц).
// Нормаль и позиция идут varying'ами от вершины (не NORMAL фрагмента), поэтому у задних граней при cull_disabled узор тот же, что у передних: на мировой решётке видна «внутренность» объёма.

#include "volume_dust.gdshaderinc"

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
	vec4 c = volume_cloud(v_wp, normalize(v_nw), normalize(CAMERA_POSITION_WORLD - v_wp), v_dist, PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y, edge);
	ALBEDO = mix(c.rgb, edge_color.rgb, edge * edge_mix);
	ALPHA = c.a;
}
