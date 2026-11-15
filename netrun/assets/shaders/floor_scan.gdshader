// Пол комнаты со строками скана (B3, ручка AssetMaterials `scan_rows`, умолчание 0 — пол остаётся облаком cloud_dark).
// Без alpha_to_coverage и без дыр: узор сплошной, ALPHA = 1. Но проход — ПРОЗРАЧНЫЙ (ALPHA пишется, depth_draw_always): фон-купол (backdrop.gdshader,
// depth_test_disabled, render_priority −128) Godot рисует в прозрачном проходе ПОСЛЕ всех непрозрачных — непрозрачный пол купол закрашивал целиком
// (кадр с очков 15.11: даже сплошной красный пол не виден). В прозрачном проходе купол идёт первым (−128), пол — поверх. Глубину пол пишет.
// Строки — аналитический узор по мировым координатам (scan_rows.gdshaderinc), без текстур и без шума; `grid_tex` здесь не читается (линии клеток 1 м сняты V11).
// Освещённость, дыхание, отклик руки, тревога у игрока — множители ЦВЕТА излучателя (неосвещённое не исчезает, а тускнеет до lit_dim); плотность — только пропуски и рука.
// Берётся только для меша `slab` (верх плиты пола, нормаль вверх): строки вдоль мировой X, шаг по мировой Z.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_always, fog_disabled;

#include "pixel_math.gdshaderinc"
#include "cloud_light.gdshaderinc"
#include "breath_touch.gdshaderinc"
#include "alarm_focus.gdshaderinc"
#include "scan_rows.gdshaderinc"

uniform float dust : hint_range(0.0, 3.0) = 1.0;   // яркость излучателей (ручка cloud, как у облака)
uniform vec4 dust_color : source_color = vec4(0.176, 0.463, 0.553, 1.0);
uniform vec4 edge_color : source_color = vec4(0.094, 0.9, 1.0, 1.0);
uniform float edge_mix : hint_range(0.0, 1.0) = 0.35;
// Цвет пустоты между излучателями = цвет очистки (AssetMaterials.VOID_BG, Environment.background_color): два разных чёрных дали бы шов у края комнаты.
uniform vec3 void_color : source_color = vec3(0.0, 0.10, 0.13);

varying vec3 v_wp;
varying flat vec3 v_row_dir;
varying flat vec3 v_phase_dir;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Мировые оси, не оси модели: у импортированной плиты пола MODEL_MATRIX может быть повёрнут (glTF Y-up), и ось строк уходила в вертикаль —
	// производные вдоль неё ноль, узор вырождался в ровный тон (кадр с очков 15.11). Комнаты выровнены по осям мира: строки вдоль X, шаг по Z.
	v_row_dir = vec3(1.0, 0.0, 0.0);
	v_phase_dir = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	// Производные — до любых веток.
	vec3 dx = dFdx(v_wp);
	vec3 dy = dFdy(v_wp);
	float edge = max(COLOR.r, max(COLOR.g, COLOR.b));
	float lift = breath_lift(v_wp);
	float tk = touch_level(v_wp);
	vec3 lit_col = vec3(1.0);
	float lit = 1.0;
	float lit_w = 0.0;
	if (lit_strength > 0.0 && cl_n > 0) {
		lit = mix(1.0, max(cloud_lit(v_wp, lit_col), tk), lit_strength);
		lit_w = lit_tint * lit;
	}
	float present = (1.0 - row_gap) * max(1.0 + touch_grow * tk, 0.0);
	vec3 point = mix(dust_color.rgb, lit_col, lit_w) * mix(lit_dim, 1.0, lit) * dust;
	point *= lift * (1.0 + touch_gain * tk);
	point = mix(point, touch_color * dust, 0.5 * tk);
	point = mix(point, edge_color.rgb, edge * edge_mix);
	point = focus_light(point, v_wp);
	ALBEDO = scan_rows(v_wp, dx, dy, v_row_dir, v_phase_dir, point, void_color, present);
	ALPHA = 1.0;   // только чтобы попасть в прозрачный проход после купола (см. шапку); дыр нет
}
