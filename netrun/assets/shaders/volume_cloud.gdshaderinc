// «Облако без основы» из частиц глитч-спрайта (cloud_dark.gdshader, ручка AssetMaterials `cloud`): простая геометрия, пропущенная через один шейдер.
// Поверхность замощается по МИРОВЫМ координатам ячейками шириной dust_cell и высотой в два раза больше (как ячейка атласа GlitchSprite 1:2): на горизонтальных гранях
// плоскость xz, на вертикальных — горизонталь вдоль грани и мировая Y (блоки всегда стоят вертикально). Каждая ячейка берёт свой кадр глитч-спрайта (покой, рывок
// в колонну, спад; кадр = время × dust_fps + случайная фаза ячейки) и рисуется, только если проходит порог плотности: плотность растёт у верхних граней и у
// скользящего взгляда (Fresnel), падает с расстоянием. Результат — ЦВЕТ и ПОКРЫТИЕ (a): пиксель, где частицы нет, не рисуется (alpha_to_coverage при MSAA: дыры мягкие, глубина
// пишется, сортировки и аддитивной перерисовки нет — за дырами видны фон и дальние объекты, как у облака точек на референсах). edge 0…1 (запечённый вес ребра или линии сетки)
// поднимает плотность до сплошного скопления. Антиалиасинг: ячейки мельче ~0,7 px дают дробное покрытие dust_cover_avg·плотность (MSAA сам превращает его в долю сэмплов): без мерцания;
// текстура читается с градиентами непрерывных координат — на границах ячеек нет швов выбора мипа.
// B3 (13.10.2026): единственный путь — «лёгкий» (хэш без sin, пятна 2D-шумом по плоскости грани: 4 хэша на фрагмент вместо 8); прежний 3D-шум и ручка cloud_lite удалены.
// Файл раньше назывался volume_dust.gdshaderinc (пыль на solid_dark удалена в B1).

uniform sampler2D glitch_tex : filter_linear_mipmap, repeat_disable;
const vec2 glitch_cells = vec2(8.0, 4.0);                         // столбцов и строк атласа
uniform float dust : hint_range(0.0, 3.0) = 0.0;                      // яркость частиц облака (ручка cloud)
uniform float dust_cell : hint_range(0.01, 0.2) = 0.018;              // ширина ячейки, м (высота вдвое больше)
uniform float dust_density : hint_range(0.0, 1.0) = 0.35;             // доля ячеек, в которых есть частица, на ровной грани вблизи
uniform float dust_fps : hint_range(0.0, 30.0) = 0.0;                 // смен кадра спрайта в секунду у каждой ячейки; 0 (умолчание) — у ячейки свой постоянный кадр. 10 кадров/с с жёсткой альфой (alpha_to_coverage) на очках рябили всю поверхность (владелец 17.10: «частицы жутко рябят»)
// Заливка вдали (рябь на очках 18.10: «вдали рябит больше», «видна граница отрисовки»): ячейка мельче dust_fill_lo px экрана не рисуется зерном (0/1 покрытие на MSAA 2× перескакивает при любом
// микродвижении головы), а заменяется ровной непрозрачной заливкой среднего цвета (тот же средний свет: цвет·плотность·dust_cover_avg); от dust_fill_hi px до dust_fill_lo зерно плавно растворяется в заливку.
uniform float dust_fill : hint_range(0.0, 1.0) = 0.0;                 // 0 — выкл. (как раньше: дробная альфа), 1 — полная заливка; ручка AssetMaterials `dust_fill`
uniform float dust_fill_edge : hint_range(0.0, 1.0) = 0.3;            // вес линий сетки и рёбер в заливке вдали (в зерне вблизи — 1): сплошные яркие линии вдали выбивались из частиц (владелец 20.10); ручка `dust_fill_edge`
uniform float dust_fill_far_min : hint_range(0.0, 1.0) = 0.3;         // яркость заливки на дистанции ≥ dust_fill_far_end относительно ближней
uniform float dust_fill_far_start = 6.0;
uniform float dust_fill_far_end = 24.0;
uniform float dust_fill_lo : hint_range(0.2, 6.0) = 2.0;
uniform float dust_fill_hi : hint_range(0.5, 8.0) = 4.0;
uniform float dust_sharp : hint_range(0.0, 1.0) = 0.0;                // 0 — как раньше; 1 — прозрачность ячейки почти 0/1 (smoothstep по яркости спрайта): меньше дробной альфы = меньше дитера a2c внутри ячейки
uniform float dust_far_start = 10.0;                                  // дальше плотность и яркость падают
uniform float dust_far_end = 40.0;
uniform vec4 dust_color : source_color = vec4(0.176, 0.463, 0.553, 1.0);  // стальная бирюза референса (45,118,141): PAL_DIM светлее, неон — только акцент
uniform vec4 dust_hot : source_color = vec4(0.62, 0.92, 1.0, 1.0);        // редкие яркие блоки (рывок): белёсый акцент

uniform float dust_patch : hint_range(0.0, 1.0) = 0.65;               // насколько плотность пятнами: 0 — ровно, 1 — большие тёмные проплешины и сгущения (как в референсе: свет лежит пятнами)
const float dust_patch_scale = 0.35;         // пятен на метр
const float dust_cover_avg = 0.3;      // средняя доля покрытия кадра спрайта (по атласу ≈ 0,2–0,35)
const float dust_edge_gain = 1.4;      // насколько вес ребра поднимает плотность (ребро = скопление частиц)

float cloud_hash(vec2 p) {  // хэш без sin: три fract/умножения
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float cloud_noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(cloud_hash(i), cloud_hash(i + vec2(1.0, 0.0)), f.x), mix(cloud_hash(i + vec2(0.0, 1.0)), cloud_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// wp, nw — мировая позиция и нормаль поверхности, vdir — единичный вектор от точки к камере, dist — дистанция, м,
// proj_px = PROJECTION_MATRIX[1][1] × VIEWPORT_SIZE.y (в пользовательских функциях Godot эти встроенные недоступны — передаёт fragment(); в fragment() P[1][1] отрицателен — берём модуль).
// dens_k — множитель плотности частиц (отклик на приближение, breath_touch.gdshaderinc; 1 — как без него; дыхание на плотность не влияет: ячейки мигали бы на тике).
// lit — освещённость 0…1 от невидимых источников (cloud_light.gdshaderinc; 1 — как без них), lit_col/lit_col_w — цвет источника и вес перекраски.
vec4 volume_cloud(vec3 wp, vec3 nw, vec3 vdir, float dist, float proj_px, float edge, float dens_k, float lit, vec3 lit_col, float lit_col_w) {
	vec3 an = abs(nw);
	vec2 plane;
	float axis;
	if (an.y >= an.x && an.y >= an.z) {
		plane = vec2(wp.x, wp.z * 0.5);
		axis = 0.0;
	} else if (an.x >= an.z) {
		plane = vec2(wp.z, wp.y * 0.5);
		axis = 1.0;
	} else {
		plane = vec2(wp.x, wp.y * 0.5);
		axis = 2.0;
	}
	vec2 coord = plane / dust_cell;
	vec2 id = floor(coord);
	vec2 f = fract(coord);
	float h = cloud_hash(id + axis * 31.0);
	float h2 = cloud_hash(id.yx + 17.0 + axis * 31.0);
	float patch_n = cloud_noise2(vec2(plane.x, plane.y * 2.0) * dust_patch_scale + vec2(axis * 7.0, 3.0));  // plane.y в 2 раза сжата (ячейка 1:2) — возвращаем метры
	float up = clamp(nw.y * 0.5 + 0.5, 0.0, 1.0);
	float ndv = 1.0 - clamp(abs(dot(nw, vdir)), 0.0, 1.0);
	float graze = ndv * ndv;
	float far_k = 1.0 - smoothstep(dust_far_start, dust_far_end, dist);
	float patch_k = mix(1.0, smoothstep(0.25, 0.75, patch_n), dust_patch);
	float lit_d = mix(lit_ambient, 1.0, smoothstep(0.0, 1.0, lit));   // плотность зерна: в темноте — доля lit_ambient, у света — полная
	float lit_e = mix(lit_edge, 1.0, lit);                            // линии сетки и рёбра гаснут слабее зерна
	float dens_g = dust_density * patch_k * (0.55 + 0.45 * up) * (1.0 + 0.7 * graze) * dens_k * lit_d;   // зерно
	float dens_e = edge * dust_edge_gain * lit_e;                                                          // линии сетки и рёбра
	float dens = clamp(dens_g + dens_e, 0.0, 1.0);
	// Заливка вдали: линии вносят меньше (dust_fill_edge) и вся заливка тускнеет с расстоянием (dust_fill_far_*) — дальний пол из тех же частиц, без резкой сетки
	float dens_f = clamp(dens_g + dens_e * dust_fill_edge, 0.0, 1.0) * mix(1.0, dust_fill_far_min, smoothstep(dust_fill_far_start, dust_fill_far_end, dist));
	if (dens < 0.004) {   // неосвещённое и дальнее — пустота: без выборки текстуры и без дробной альфы
		return vec4(0.0);
	}
	float px_world = 2.0 * max(dist, 0.1) / max(abs(proj_px), 1.0);
	float cell_px = dust_cell / px_world;
	float sharp = smoothstep(0.7, 2.0, cell_px);
	float lit_b = mix(lit_dim, 1.0, lit) * dust;                      // яркость частиц: в темноте тусклее
	vec3 avg_rgb = mix(mix(dust_color.rgb, dust_hot.rgb, edge * 0.5), lit_col, lit_col_w) * lit_b;
	float fill_w = dust_fill * (1.0 - smoothstep(dust_fill_lo, dust_fill_hi, cell_px));
	if (fill_w >= 0.999 || (dust_fill <= 0.0 && sharp < 0.02)) {  // ячейка мельче порога: только средняя засветка — без выборки текстуры (дальние плиты и потолок: основная масса фрагментов)
		if (dust_fill > 0.0) {
#ifdef CLOUD_A2C
			return vec4(avg_rgb * dens_f * dust_cover_avg * far_k, 1.0);   // заливка: яркость среднего света, цвет гаснет вдаль (альфа 1 — без дитера a2c)
#else
			return vec4(avg_rgb, dens_f * dust_cover_avg * far_k);   // непрозрачная грань: альфа — яркость заливки (cloud_dark множит цвет на неё), поэтому неоновая обводка рёбер вдали тускнеет вместе с ней
#endif
		}
		return vec4(avg_rgb, clamp(dens * dust_cover_avg * far_k, 0.0, 1.0));
	}
	float n = glitch_cells.x * glitch_cells.y;
	float frame = floor(mod(TIME * dust_fps + h * n, n));
	vec2 cellxy = vec2(mod(frame, glitch_cells.x), floor(frame / glitch_cells.x));
	vec2 uv = (cellxy + f) / glitch_cells;
	// градиенты — от непрерывных координат ячеек, иначе на границе ячейки скачок и швы мипов
	float s = textureGrad(glitch_tex, uv, dFdx(coord) / glitch_cells, dFdy(coord) / glitch_cells).r;
	s = mix(s, smoothstep(0.35, 0.65, s), dust_sharp);
	float present = step(h2, dens);
	float a = mix(dens * dust_cover_avg, s * present, sharp);
	vec3 base = mix(dust_color.rgb, dust_hot.rgb, smoothstep(0.55, 1.0, s) * step(0.82, h) + edge * 0.5);
	vec4 cell = vec4(mix(base, lit_col, lit_col_w) * lit_b, clamp(a * far_k, 0.0, 1.0));
	if (fill_w > 0.0) {   // зерно → заливка: цвет и покрытие смешиваются по весу, на границе режимов нет скачка яркости
#ifdef CLOUD_A2C
		float fill_a = 1.0;
		vec3 fill_rgb = avg_rgb * dens_f * dust_cover_avg * far_k;
#else
		float fill_a = dens_f * dust_cover_avg * far_k;   // см. выше: альфа заливки — её яркость
		vec3 fill_rgb = avg_rgb;
#endif
		float ao = cell.a * (1.0 - fill_w) + fill_a * fill_w;   // «зерно поверх заливки» с весом (1 − fill_w)
		cell = vec4((cell.rgb * cell.a * (1.0 - fill_w) + fill_rgb * fill_a * fill_w) / max(ao, 0.001), ao);
	}
	return cell;
}
