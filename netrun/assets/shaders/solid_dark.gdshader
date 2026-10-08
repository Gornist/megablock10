// Тёмная непрозрачная основа (силуэт, закрывает то, что за ней). Свет несёт цвет вершины (альфа до Godot не доходит): чёрный — нет света, цвет — свет, × edge_glow —
// так у тайлов пола и потолка светится тонкий контур верхней грани (рамка 1,4 см), остальное чёрное. Фреснеля больше нет (у чёрных вершин он был нулевой).
shader_type spatial;
render_mode unshaded, cull_back, fog_disabled;

// Не чистый чёрный, а тёмная бирюза темнее фона-пустоты (AssetMaterials.VOID_BG): у референса CDPR чистого чёрного ≈ 0 %, плиты читаются силуэтом на фоне.
uniform vec4 base_color : source_color = vec4(0.0, 0.07, 0.09, 1.0);
uniform float edge_glow : hint_range(0.0, 4.0) = 0.75;        // общая яркость контура (почти прозрачный: тусклый, фон просвечивает сквозь свет)
uniform float edge_uneven : hint_range(0.0, 1.0) = 0.92;    // неравномерность: 0 — ровная линия, 1 — от почти погасшей до полной яркости
uniform float edge_noise_scale : hint_range(1.0, 40.0) = 14.0; // пятен света на метр вдоль контура
uniform float edge_drift : hint_range(0.0, 1.0) = 0.12;      // медленное «плавание» пятен света, 1/с
// Контур по UV (по умолчанию выключен, включает AssetMaterials для мешей `*_plates`: плиты террас и полос env/floor_v2/v4): у плиты на верхней грани UV0 = локальные метры
// от центра, UV1 = полуразмеры плиты; светится кайма шириной uv_rim по краю верха. Так плита — один квад (2 треугольника), а не 90 треугольников с вырезанной рамкой.
// У боковых граней UV1 огромны: каймы нет.
uniform float uv_rim : hint_range(0.0, 0.2) = 0.0;
uniform vec4 tint : source_color = vec4(1.0);
uniform float tint_amount : hint_range(0.0, 1.0) = 0.0;
// Сетка клеток хода ТЕКСТУРОЙ на верхних гранях (пол): линии клетки 1 м запечены в grid_tex (AssetMaterials._grid_texture, мипмапы), выборка по МИРОВЫМ x,z
// с анизотропной фильтрацией: издали и под скользящим углом линия плавно тускнеет по мипам, а не мерцает и не «лесенкой» (в отличие от точек и шейдерных линий на границе пикселя).
// grid_alpha = 0 — выключено (по умолчанию). grid_origin — мировые xz угла клетки, если плита стоит не на целых метрах. Анизотропия берётся из настроек проекта
// (rendering/textures/default_filters/anisotropic_filtering_level).
uniform sampler2D grid_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float grid_alpha : hint_range(0.0, 2.0) = 0.0;
uniform vec2 grid_origin = vec2(0.0);
// Борьба с мерцанием кромок плит (пол, потолок, дальние пласты; включает AssetMaterials для мешей плит, ручки [assets] plate_*): у плиты толщиной 3 см светятся и боковая полоска кромки,
// и контур верха, а ниже — край вуали и начала штрихов: на 6–10 м они сходятся в один пиксель и дают муар. Три независимых меры:
uniform float rim_top_only = 0.0;   // 1 — светится только лицевая грань (нормаль вверх/вниз), боковая полоска кромки не светится: одна линия вместо двух
uniform float plate_flat = 0.0;     // 1 — боковые грани плиты отбрасываются (плита без толщины, плоскость): нет «двойного» силуэта 3 см
uniform float rim_far_min = 1.0;    // яркость кромки на дистанции ≥ rim_far_end (1 — не гасить): кромка гаснет раньше, чем линии сливаются в пиксель
uniform float rim_far_start = 8.0;
uniform float rim_far_end = 20.0;
// «Кромка внутрь» (лесенка силуэта без MSAA): пик света сдвинут с геометрического края на 1–1,5 см внутрь, у самого силуэта свет гаснет до (1 − edge_soft). Подробности — edge_soft.gdshaderinc.
uniform float edge_soft : hint_range(0.0, 1.0) = 0.0;
#include "edge_soft.gdshaderinc"

// Перекраска тиром сохраняет чёрное и белое: у чёрных вершин (тайлы пола) кайма остаётся нулевой.
vec3 recolor(vec3 c) {
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	return mix(tint.rgb * mx, c, mn / max(mx, 0.0001));
}

varying vec3 v_wp;
varying vec2 v_uv;
varying vec2 v_hs;
varying float v_top;   // нормаль.y в пространстве модели: верх плиты смотрит в +Y (нужна сетке)
varying float v_face;  // |нормаль.y| в пространстве модели: 1 — лицевая грань плиты (верх или низ), 0 — боковая
varying float v_dist;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}
// Гладкий шум по мировой позиции: у соседних тайлов своё пятно света, у одного ребра свет вдоль него неровный.
float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_uv = UV;
	v_hs = UV2;
	v_top = NORMAL.y;
	v_face = abs(NORMAL.y);
	v_dist = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}

void fragment() {
	float n = vnoise(v_wp * edge_noise_scale + vec3(TIME * edge_drift, 0.0, TIME * edge_drift * 0.7));
	float lit = mix(1.0, smoothstep(0.38, 0.62, n), edge_uneven);
	float rim_k = 1.0;
	if (uv_rim > 0.0) {
		vec2 q = v_hs - abs(v_uv);
		float m = min(q.x, q.y);
		rim_k = 1.0 - smoothstep(uv_rim * 0.4, uv_rim, m);
		rim_k *= mix(1.0, smoothstep(0.0, uv_rim * 0.35, m), edge_soft);  // у самого края плиты свет гаснет: силуэт тёмный, линия чуть внутри
	}
	if (plate_flat > 0.5 && v_face < 0.5) {
		discard;
	}
	float rim_gain = 1.0;
	if (rim_top_only > 0.5 && v_face < 0.5) {
		rim_gain = 0.0;
	}
	rim_gain *= mix(1.0, rim_far_min, smoothstep(rim_far_start, rim_far_end, v_dist));
	float soft_k = edge_soft_gain(max(COLOR.r, max(COLOR.g, COLOR.b)), edge_soft);
	vec3 col = base_color.rgb + mix(COLOR.rgb, recolor(COLOR.rgb), tint_amount) * edge_glow * lit * rim_k * rim_gain * soft_k;
	if (grid_alpha > 0.0 && v_top > 0.9) {
		float g = texture(grid_tex, v_wp.xz - grid_origin).r;
		vec3 gc = tint_amount > 0.0 ? tint.rgb : vec3(0.094, 0.9, 1.0);
		col += gc * g * grid_alpha;
	}
	ALBEDO = col;
}
