// «Вуаль» на боковых гранях плит пола/потолка (меши `*_skirt`): слабое светящееся свечение между штрихами, а не стекло и не стена.
// Один вертикальный квад на грань: яркий у кромки плиты (альфа вершины = плотность) и гаснущий книзу до длины штрихов.
// Аддитивный, без освещения, без записи глубины, без чтения буфера глубины (без depth-fade). Двусторонний: смотрим на грань и снаружи, и из-под плиты.
// Цвет и плотность — из цвета вершин (RGB, A). Очень низкая итоговая непрозрачность (veil_alpha): штрихи остаются главным примитивом.
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, fog_disabled;

#include "alarm_focus.gdshaderinc"

uniform float glow : hint_range(0.0, 4.0) = 1.0;
uniform float veil_alpha : hint_range(0.0, 0.5) = 0.065;   // итоговая непрозрачность у кромки: «очень прозрачная»
uniform float veil_scale : hint_range(0.0, 4.0) = 1.0;    // множитель итоговой альфы вуали (ручка veil_scale; 0 — меш скрывается совсем; > 1 — усилить: очки П5 одобрили вуаль потолка)
// Завеса ВВЕРХ от верхней кромки плит пола (квады с высотой в UV2.x, env._slab_rise): отдельные ручки, чтобы не трогать вуаль вниз.
uniform float rise_gain : hint_range(0.0, 8.0) = 1.0;     // множитель альфы завесы вверх (ручка tile_glow); 0 — квады схлопываются, заливку не тратят
uniform float rise_scale : hint_range(0.1, 3.0) = 1.0;    // высота завесы вверх относительно модельной (ручка tile_glow_h)
const float falloff = 2.4;      // крутизна затухания книзу: больше — вуаль плотнее прижата к кромке
#include "tint_common.gdshaderinc"
// Верх вуали плотнее всего и лежит на нижнем краю плиты, на 3 см ниже светящейся кромки: издали две яркие линии рядом сливаются в пиксель и мерцают.
// top_fade — доля высоты вуали сверху, на которой плотность нарастает с нуля: вуаль «отрывается» от кромки плиты (0,12 принято на очках; 0 — как раньше).
// Пятнистость и дрейф пятен вдоль грани убраны (принято: ровная и статичная вуаль — без «лава-лампы»).
uniform float top_fade : hint_range(0.0, 0.5) = 0.12;
// Затухание по расстоянию до камеры (замена depth-fade) и яркость растёт к горизонту, как у штрихов (far_gain). 1 — выключено.
const float fade_start = 60.0;
const float fade_end = 90.0;
uniform float intensity = 1.0; // общий множитель яркости (отражение в полу = 0.2)
uniform float far_gain : hint_range(1.0, 6.0) = 1.0;
uniform float far_start = 20.0;
uniform float far_end = 60.0;

varying float v_dist;
varying float v_rise;   // 1 — квад завесы вверх (UV2.x > 0), 0 — обычная вуаль
varying vec3 v_wp;


void vertex() {
	v_rise = UV2.x > 0.0 ? 1.0 : 0.0;
	if (v_rise > 0.5 && UV.y > 0.5) {  // дальний край квада: высота = модельная (UV2.x, м) × rise_scale; основание у кромки плиты не двигается
		VERTEX.y += (rise_scale - 1.0) * UV2.x;
	}
	v_dist = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (v_rise > 0.5 && rise_gain <= 0.0) {
		POSITION = vec4(2.0, 2.0, 2.0, 1.0);  // завеса выключена: квад вне экрана
	} else {
		POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	}
}

void fragment() {
	float dens = pow(COLOR.a, falloff);
	if (top_fade > 0.0) {
		dens *= smoothstep(0.0, top_fade, UV.y);  // UV.y: 0 вверху вуали, 1 внизу
	}
	float fade = 1.0 - smoothstep(fade_start, fade_end, v_dist);
	vec3 col = mix(COLOR.rgb, recolor(COLOR.rgb), tint_amount);
	ALBEDO = focus_light(col * glow * mix(1.0, far_gain, smoothstep(far_start, far_end, v_dist)), v_wp);
	ALPHA = dens * veil_alpha * fade * intensity * mix(veil_scale, rise_gain, v_rise);
}
