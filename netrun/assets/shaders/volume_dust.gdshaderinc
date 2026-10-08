// «Волюметрик из частиц» на твёрдых поверхностях (ручка AssetMaterials `dust`, solid_dark): простая геометрия, пропущенная через один шейдер.
// Поверхность замощается по МИРОВЫМ координатам ячейками шириной dust_cell и высотой в два раза больше (как ячейка атласа GlitchSprite 1:2): на горизонтальных гранях
// плоскость xz, на вертикальных — горизонталь вдоль грани и мировая Y (блоки всегда стоят вертикально). Каждая ячейка берёт свой кадр глитч-спрайта (покой, рывок
// в колонну, спад; кадр = время × dust_fps + случайная фаза ячейки) и рисуется, только если проходит порог плотности: плотность растёт у верхних граней и у
// скользящего взгляда (Fresnel), падает с расстоянием. Нет геометрии, нет прозрачности, нет перерисовки: свет добавляется к тёмной непрозрачной основе.
// Антиалиасинг: ячейки мельче ~1,5 px гаснут, вместо них идёт ровная «средняя» засветка (dust_mean); текстура читается с градиентами непрерывных координат —
// на границах ячеек нет швов выбора мипа. Край объёма — рваная пыль, а не линия света: ступеньки «яркое по тёмному» нет.

uniform sampler2D glitch_tex : filter_linear_mipmap, repeat_disable;
uniform vec2 glitch_cells = vec2(8.0, 4.0);                         // столбцов и строк атласа
uniform float dust : hint_range(0.0, 3.0) = 0.0;                      // яркость пыли, 0 — выкл.
uniform float dust_cell : hint_range(0.01, 0.2) = 0.035;              // ширина ячейки, м (высота вдвое больше)
uniform float dust_density : hint_range(0.0, 1.0) = 0.55;             // доля ячеек, в которых есть частица, на ровной грани вблизи
uniform float dust_fps : hint_range(1.0, 30.0) = 10.0;
uniform float dust_mean : hint_range(0.0, 0.5) = 0.12;                // средняя засветка вместо ячеек мельче пикселя (≈ средняя яркость спрайта × плотность)
uniform float dust_far_start = 10.0;                                   // дальше плотность и яркость падают
uniform float dust_far_end = 40.0;
uniform vec4 dust_color : source_color = vec4(0.176, 0.463, 0.553, 1.0);  // стальная бирюза референса (45,118,141): PAL_DIM светлее, неон — только акцент
uniform vec4 dust_hot : source_color = vec4(0.62, 0.92, 1.0, 1.0);        // редкие яркие блоки (рывок): белёсый акцент

uniform float dust_patch : hint_range(0.0, 1.0) = 0.65;               // насколько плотность пятнами: 0 — ровно, 1 — большие тёмные проплешины и сгущения (как в референсе: свет лежит пятнами)
uniform float dust_patch_scale : hint_range(0.05, 3.0) = 0.35;         // пятен на метр

float dust_hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}
float dust_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(dust_hash(i), dust_hash(i + vec3(1, 0, 0)), f.x), mix(dust_hash(i + vec3(0, 1, 0)), dust_hash(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(dust_hash(i + vec3(0, 0, 1)), dust_hash(i + vec3(1, 0, 1)), f.x), mix(dust_hash(i + vec3(0, 1, 1)), dust_hash(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}

// Вклад пыли в цвет пикселя. wp, nw — мировая позиция и нормаль поверхности, vdir — единичный вектор от точки к камере, dist — дистанция, м,
// proj_px = PROJECTION_MATRIX[1][1] × VIEWPORT_SIZE.y (в пользовательских функциях Godot эти встроенные недоступны — передаёт fragment()).
vec3 volume_dust_color(vec3 wp, vec3 nw, vec3 vdir, float dist, float proj_px) {
	if (dust <= 0.0) {
		return vec3(0.0);
	}
	vec3 an = abs(nw);
	vec2 plane;
	float axis;
	if (an.y >= an.x && an.y >= an.z) {
		plane = vec2(wp.x, wp.z * 0.5);          // горизонтальная грань: ячейка 1 × 2 в xz
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
	float h = dust_hash(vec3(id, axis));
	float h2 = dust_hash(vec3(id.yx + 17.0, axis));
	// плотность: верх ярче, скользящий взгляд плотнее (поверхность «накапливается» вдоль луча), даль реже
	float up = clamp(nw.y * 0.5 + 0.5, 0.0, 1.0);
	float graze = pow(1.0 - clamp(abs(dot(nw, vdir)), 0.0, 1.0), 2.0);
	float far_k = 1.0 - smoothstep(dust_far_start, dust_far_end, dist);
	float patch_k = mix(1.0, smoothstep(0.25, 0.75, dust_noise(wp * dust_patch_scale + vec3(0.0, axis * 7.0, 0.0))), dust_patch);
	float dens = clamp(dust_density * patch_k * (0.55 + 0.45 * up) * (1.0 + 0.7 * graze), 0.0, 1.0);
	// размер ячейки на экране, px: мировой размер пикселя на дистанции 2·d / (P[1][1]·высота вьюпорта); в фрагментном шейдере P[1][1] отрицателен (отражение по Y) — берём модуль
	float px_world = 2.0 * max(dist, 0.1) / max(abs(proj_px), 1.0);
	float cell_px = dust_cell / px_world;
	float sharp = smoothstep(0.7, 2.0, cell_px);   // 0 — ячейка мельче пикселя: только средняя засветка
	float n = glitch_cells.x * glitch_cells.y;
	float frame = floor(mod(TIME * dust_fps + h * n, n));
	vec2 cellxy = vec2(mod(frame, glitch_cells.x), floor(frame / glitch_cells.x));
	vec2 uv = (cellxy + f) / glitch_cells;
	// градиенты — от непрерывных координат ячеек, иначе на границе ячейки скачок и швы мипов
	float s = textureGrad(glitch_tex, uv, dFdx(coord) / glitch_cells, dFdy(coord) / glitch_cells).r;
	float present = step(h2, dens);
	vec3 base = mix(dust_color.rgb, dust_hot.rgb, smoothstep(0.55, 1.0, s) * step(0.82, h));
	vec3 particle = base * s * present;
	vec3 avg = dust_color.rgb * dust_mean * dens * 2.0;
	return (particle * sharp + avg * (1.0 - sharp)) * dust * far_k;
}
