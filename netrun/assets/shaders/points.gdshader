// Облако точек: каждая точка — квадрат из 4 вершин, всегда обращённый к камере, круглая мягкая точка.
// Контракт с lib.py (Blender): квадрат лежит в плоскости XZ Blender (в Godot — XY) с центром c и полуразмером h;
// UV0 — углы квадрата, UV1.x = h. Центр восстанавливаем вычитанием смещения угла из позиции вершины.
// Мерцание медленное и неглубокое (комфорт в VR); цвет и яркость — из цвета вершин.
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, fog_disabled;

uniform float glow : hint_range(0.0, 6.0) = 1.4;
uniform float lattice : hint_range(0.0, 0.5) = 0.0;  // шаг мировой решётки, м: центры прищёлкиваются к ней (0 = выкл.), эффект «объёмного дисплея»
const float twinkle = 0.15;
const float twinkle_speed = 0.6;
// «Дыхание» поля точек (пол, рёбра тайлов): по полю бежит волна яркости и вместе с ней пульсирует размер точек.
uniform float wave : hint_range(0.0, 1.0) = 0.6;          // глубина волны яркости
const float size_wave = 0.45;    // глубина пульсации размера
const float wave_speed = 0.9;
const float wave_scale = 1.1;    // волн на метр
#include "tint_common.gdshaderinc"

// Затухание по расстоянию до камеры (замена depth-fade: буфер глубины не читаем, на мобильном дорого).
const float fade_start = 60.0;
const float fade_end = 90.0;
uniform float intensity = 1.0; // общий множитель яркости (отражение в полу = 0.2)
// Минимальный диаметр точки в пикселях экрана (точка меньше пикселя мерцает): дальше квад растёт до min_px, яркость падает по площади. 0 — выключено.
uniform float min_px : hint_range(0.0, 6.0) = 2.0;
// Доля точек, что остаются (ручка AssetMaterials `point_keep`, только точки окружения; очки П5: вдали точки сильно мерцают): выпавшие схлопываются в вершинном шейдере, заливку не тратят. 0 — все убраны.
uniform float keep_frac : hint_range(0.0, 1.0) = 1.0;

varying vec3 v_wp;
varying float v_dist;
varying float v_comp;  // 1 / (во сколько раз квад увеличен до min_px)²

float dist_fade() {
	return 1.0 - smoothstep(fade_start, fade_end, v_dist);
}

varying float v_phase;
varying float v_wave;

void vertex() {
	float h = UV2.x;
	vec3 c = VERTEX - vec3((UV.x - 0.5) * 2.0 * h, (0.5 - UV.y) * 2.0 * h, 0.0);
	v_phase = dot(c, vec3(12.9, 78.2, 37.7));
	v_wp = (MODEL_MATRIX * vec4(c, 1.0)).xyz;
	if (lattice > 0.0) {
		v_wp = floor(v_wp / lattice + 0.5) * lattice;
	}
	v_wave = 0.5 + 0.5 * sin((v_wp.x + 0.6 * v_wp.z) * wave_scale * 3.14159 - TIME * wave_speed);
	vec4 mv = VIEW_MATRIX * vec4(v_wp, 1.0);
	v_dist = -mv.z;
	float hs = h * (1.0 + size_wave * (v_wave - 0.5) * 2.0);
	float sk = 1.0;
	if (min_px > 0.0) {  // мировой размер пикселя на дистанции точки: 2·d / (P[1][1] · высота вьюпорта); полуразмер точки ≥ min_px / 2
		float px = 2.0 * max(v_dist, 0.1) / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
		sk = max(1.0, 0.5 * min_px * px / max(hs, 0.0001));
	}
	v_comp = 1.0 / (sk * sk);
	mv.xy += vec2(UV.x - 0.5, 0.5 - UV.y) * 2.0 * hs * sk;
	bool dropped = keep_frac < 1.0 && fract(sin(v_phase * 3.7 + 1.3) * 43758.5453) >= keep_frac;  // keep_frac = 0 — выпадают все
	POSITION = dropped ? vec4(2.0, 2.0, 2.0, 1.0) : PROJECTION_MATRIX * mv;
}

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float soft = smoothstep(1.0, 0.25, d);
	float tw = 1.0 - twinkle + twinkle * sin(TIME * twinkle_speed + v_phase + (v_wp.x + v_wp.z) * 1.7); // волны мерцания бегут по полу
	ALBEDO = mix(COLOR.rgb, recolor(COLOR.rgb), tint_amount) * glow;
	ALPHA = soft * COLOR.a * tw * (1.0 - wave + wave * v_wave) * dist_fade() * intensity * v_comp;
}
