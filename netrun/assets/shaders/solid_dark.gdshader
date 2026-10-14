// Тёмная непрозрачная основа (силуэт, закрывает то, что за ней). Свет несёт цвет вершины (альфа до Godot не доходит): чёрный — нет света, цвет — свет, × edge_glow —
// так у тайлов пола и потолка светится тонкий контур верхней грани (рамка 1,4 см), остальное чёрное. Фреснеля больше нет (у чёрных вершин он был нулевой).
// Свет рёбер ровный и статичный (принято на очках: шум и дрейф «лава-лампы», «кромка внутрь», клипы пересвета, пыль, контур по UV и discard боковых граней убраны — рефактор B1).
shader_type spatial;
render_mode unshaded, cull_back, fog_disabled;

// Не чистый чёрный, а тёмная бирюза темнее фона-пустоты (AssetMaterials.VOID_BG): у референса CDPR чистого чёрного ≈ 0 %, плиты читаются силуэтом на фоне.
uniform vec4 base_color : source_color = vec4(0.0, 0.07, 0.09, 1.0);
uniform float edge_glow : hint_range(0.0, 4.0) = 0.75;        // общая яркость контура (почти прозрачный: тусклый, фон просвечивает сквозь свет)
uniform vec4 tint : source_color = vec4(1.0);
uniform float tint_amount : hint_range(0.0, 1.0) = 0.0;
// Сетка клеток хода ТЕКСТУРОЙ на верхних гранях (пол): линии клетки 1 м запечены в grid_tex (AssetMaterials._grid_texture, мипмапы), выборка по МИРОВЫМ x,z
// с анизотропной фильтрацией: издали и под скользящим углом линия плавно тускнеет по мипам, а не мерцает и не «лесенкой» (в отличие от точек и шейдерных линий на границе пикселя).
// grid_alpha = 0 — выключено. grid_origin — мировые xz угла клетки, если плита стоит не на целых метрах. Анизотропия берётся из настроек проекта
// (rendering/textures/default_filters/anisotropic_filtering_level).
uniform sampler2D grid_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float grid_alpha : hint_range(0.0, 2.0) = 0.0;
uniform vec2 grid_origin = vec2(0.0);
// Борьба с мерцанием кромок плит (пол, потолок, дальние пласты; включает AssetMaterials для мешей плит, ручки [assets] rim_*): у плиты светятся тонкая боковая полоска (3 см)
// и контур верха, а ниже — край вуали: на 6–10 м они сходятся в один пиксель и дают муар. Три независимых меры:
uniform float rim_top_only = 0.0;   // 1 — светится только лицевая грань (нормаль вверх/вниз), боковая полоска кромки не светится: одна линия вместо двух
uniform float rim_far_min = 1.0;    // яркость кромки на дистанции ≥ rim_far_end (1 — не гасить): кромка гаснет раньше, чем линии сливаются в пиксель
uniform float rim_far_start = 8.0;
uniform float rim_far_end = 20.0;
// Гашение кромки по её ширине НА ЭКРАНЕ (очки: тонкие кромки по низу дальних висящих плит тоньше пикселя, рвутся в пунктир и мерцают): физическая ширина кромки rim_world_w (инсет 1,4 см)
// переводится в пиксели через проекцию текущего глаза (не зависит от FOV и разрешения), яркость растёт от 0 при ширине 0,35·rim_min_px до полной при ширине ≥ rim_min_px. 0 — выключено.
uniform float rim_min_px : hint_range(0.0, 8.0) = 0.0;
uniform float rim_world_w = 0.014;
// Профиль света ребра: градиент вершин (1 на стыке граней → 0 на 3 см) — линейная «палатка» с изломом на пике; при MSAA (в Godot нет centroid) пиксельный сэмпл у стыка лежит
// вне тонкого треугольника и экстраполирует пик — светлая «линия Маха», мигающая при движении. 1 — smoothstep по яркости вершины (нулевой наклон на пике и у подножия).
uniform float edge_round : hint_range(0.0, 1.0) = 1.0;

// Перекраска тиром сохраняет чёрное и белое: у чёрных вершин (тайлы пола) кайма остаётся нулевой.
vec3 recolor(vec3 c) {
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	return mix(tint.rgb * mx, c, mn / max(mx, 0.0001));
}

varying vec3 v_wp;
varying float v_top;   // нормаль.y в пространстве модели: верх плиты смотрит в +Y (нужна сетке)
varying float v_face;  // |нормаль.y| в пространстве модели: 1 — лицевая грань плиты (верх или низ), 0 — боковая
varying float v_dist;

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_top = NORMAL.y;
	v_face = abs(NORMAL.y);
	v_dist = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}

void fragment() {
	float rim_gain = 1.0;
	if (rim_top_only > 0.5 && v_face < 0.5) {
		rim_gain = 0.0;
	}
	rim_gain *= mix(1.0, rim_far_min, smoothstep(rim_far_start, rim_far_end, v_dist));
	if (rim_min_px > 0.0) {
		float rim_px = rim_world_w * abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y * 0.5 / max(v_dist, 0.1);  // ширина кромки на экране, px
		rim_gain *= smoothstep(0.35, 1.0, rim_px / rim_min_px);
	}
	vec3 vc = COLOR.rgb;
	if (edge_round > 0.0) {
		float rk = max(vc.r, max(vc.g, vc.b));
		vc *= mix(1.0, smoothstep(0.0, 1.0, rk) / max(rk, 0.0001), edge_round);
	}
	vec3 col = base_color.rgb + mix(vc, recolor(vc), tint_amount) * edge_glow * rim_gain;
	if (grid_alpha > 0.0 && v_top > 0.9) {
		float g = texture(grid_tex, v_wp.xz - grid_origin).r;
		vec3 gc = tint_amount > 0.0 ? tint.rgb : vec3(0.094, 0.9, 1.0);
		col += gc * g * grid_alpha;
	}
	ALBEDO = col;
}
