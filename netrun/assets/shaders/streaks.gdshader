// Штрих: вертикальная светящаяся чёрточка (основной примитив стиля, по референсам Blackwall): мягкий поперечный профиль,
// затухание к концам, «бусины» вдоль длины, которые ползут вверх. Один квадрат (2 треугольника) заменяет цепочку точек.
// Контракт с lib.py: квадрат в плоскости XZ Blender (в Godot XY) с центром c, полуширина w, полувысота h; UV0 — углы,
// UV1 = (w, h). Вертикаль — мировая ось Y, к камере разворачивается только по горизонтали (цилиндрический биллборд).
// Анимация целиком в шейдере (по гифкам референса): бегущая волна яркости вдоль стены, ползущие бусины, «дыхание» длины
// и покачивание, слабая пульсация яркости у каждого штриха (стены живые, не статика), реакция на касание: штрихи прогибаются от точки касания, по высоте касания идёт красная полоса.
// Всё медленное и неглубокое (комфорт в VR: никаких вспышек и резких движений).
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, fog_disabled;

uniform float lattice : hint_range(0.0, 0.5) = 0.0;  // шаг мировой решётки, м: центры прищёлкиваются к ней (0 = выкл.), эффект «объёмного дисплея»
uniform float glow : hint_range(0.0, 6.0) = 1.6;
uniform float bead_freq : hint_range(0.0, 60.0) = 14.0;   // бусин на метр
uniform float bead_depth : hint_range(0.0, 1.0) = 0.35;
uniform float bead_speed : hint_range(0.0, 2.0) = 0.12;   // бусины ползут вверх, м/с
uniform float end_fade : hint_range(0.05, 1.0) = 0.35;
uniform float edge_sharp : hint_range(1.0, 12.0) = 5.0;   // больше — тоньше ядро
// Мягкий ореол (люминесценция): 0 — выкл. (существа, аватары, дека), у окружения ставит AssetMaterials.apply. Квад расширяется в halo_width раз,
// ядро остаётся прежней мировой ширины, вокруг — широкий слабый ореол: соседние штрихи сливаются в светящуюся дымку. Без буфера глубины и без постобработки.
uniform float halo : hint_range(0.0, 1.0) = 0.0;
uniform float halo_width : hint_range(1.0, 6.0) = 2.5;
uniform float halo_sharp : hint_range(0.5, 8.0) = 2.2;   // больше — уже ореол (в долях расширенного квада)
uniform float pulse : hint_range(0.0, 1.0) = 0.45;        // глубина бегущей волны яркости
uniform float pulse_speed : hint_range(0.0, 3.0) = 1.0;
uniform float pulse_scale : hint_range(0.0, 8.0) = 1.6;   // волн на метр вдоль стены
uniform float breathe : hint_range(0.0, 0.8) = 0.3;       // «дыхание/горение»: размах изменения длины штриха (две частоты, как пламя)
uniform float breathe_speed : hint_range(0.0, 3.0) = 0.7;
uniform float sway : hint_range(0.0, 0.1) = 0.012;       // покачивание штриха из стороны в сторону, м
uniform float sway_speed : hint_range(0.0, 3.0) = 0.6;
uniform float shimmer : hint_range(0.0, 0.8) = 0.3;      // у каждого штриха своя слабая пульсация яркости
uniform float shimmer_speed : hint_range(0.0, 4.0) = 1.3;
uniform float anchor : hint_range(-1.0, 1.0) = -1.0;     // что неподвижно при изменении длины: -1 основание (стены, существа), +1 верх (подвесные штрихи под полом), 0 центр
uniform vec3 touch_pos = vec3(0.0);                       // касание: мировая точка
uniform float touch_radius = 0.0;                         // 0 — выключено
uniform vec4 touch_color : source_color = vec4(1.0, 0.12, 0.24, 1.0);
uniform vec4 tint : source_color = vec4(1.0);
uniform float tint_amount : hint_range(0.0, 1.0) = 0.0;
// Corruption: красный «шрам» в радиусе от точки (мировые координаты): цвет уходит в corrupt_color, часть клеток пропадает.
// Дискретные клетки по сетке, без анимации: комфорт в VR (никаких вспышек). Выключено при corrupt_radius = 0.
uniform vec3 corrupt_pos = vec3(0.0);
uniform float corrupt_radius = 0.0;
uniform vec4 corrupt_color : source_color = vec4(1.0, 0.12, 0.24, 1.0);
// Затухание по расстоянию до камеры (замена depth-fade: буфер глубины не читаем, на мобильном дорого).
uniform float fade_start = 60.0;
uniform float fade_end = 90.0;
uniform float intensity = 1.0; // общий множитель яркости (отражение в полу = 0.2)
// Яркий горизонт (референс: штрихи копятся в бирюзовый туман на уровне глаз): множитель яркости растёт с расстоянием от far_start до far_end
// до far_gain и применяется до затухания по расстоянию. 1 — выключено (по умолчанию).
uniform float far_gain : hint_range(1.0, 6.0) = 1.0;
uniform float far_start = 20.0;
uniform float far_end = 60.0;
// Минимальная полная ширина штриха в пикселях экрана (антиалиасинг без MSAA/TAA): штрих тоньше пикселя на дистанции мерцает и «ползёт лесенкой».
// Дальше квад расширяется до min_px, яркость падает во столько же раз (свет по площади тот же). 0 — выключено.
uniform float min_px : hint_range(0.0, 4.0) = 1.5;
// Ручки против ряби «эквалайзеров» (вертикальные штрихи у плит; ставит AssetMaterials.apply для штрихов окружения, ручки [assets] streak_*). Все выключены по умолчанию.
uniform float far_dim_min : hint_range(0.0, 1.0) = 1.0;     // яркость штриха на дистанции ≥ far_dim_end (1 — не гасить): как кромка плит, гаснут раньше, чем сливаются в пиксель
uniform float far_dim_start = 8.0;
uniform float far_dim_end = 25.0;
uniform float keep_frac : hint_range(0.0, 1.0) = 1.0;       // доля штрихов, что остаются (по хешу штриха, стабильно от кадра к кадру); остальные схлопываются в вершинном шейдере, заливку не тратят
uniform float len_scale : hint_range(0.1, 2.0) = 1.0;       // длина штриха от основания/якоря
uniform float scatter : hint_range(0.0, 0.5) = 0.0;         // м: случайный сдвиг центра штриха по x, z (хеш штриха, стабильно): ломает ровные параллельные ряды, из-за которых при ползании по пикселям возникает муар; у ICE форма неровная — рябь слабее
uniform float px_fade : hint_range(0.0, 1.0) = 0.0;        // 1 — штрих уже ~0,4 px по номиналу гаснет совсем, к 2 px — полная яркость: тонкие штрихи не «ползут лесенкой», а тускнеют (min_px сохраняет яркость, это — нет)

varying float v_pxk;
varying vec3 v_wp;
varying float v_dist;

float corrupt_k() {
	return corrupt_radius > 0.0 ? 1.0 - smoothstep(corrupt_radius * 0.12, corrupt_radius, distance(v_wp, corrupt_pos)) : 0.0;
}
float cell_hash(float salt) {
	return fract(sin(dot(floor(v_wp * vec3(2.5, 16.0, 2.5)) + salt, vec3(12.9, 78.2, 37.7))) * 43758.5);
}
// Порча горизонтальными полосами (глитч, как в референсе Blackwall): полоса либо цвета ассета, либо corrupt_color, без серого посередине.
float corrupt_mask(float k) {
	return k > 0.0 ? step(cell_hash(0.0), k) : 0.0;  // при k = 0 шрама нет: без защиты клетка с нулевым хешем краснела бы сама
}
float corrupt_hole(float m) {
	return 1.0 - m * step(cell_hash(7.0), 0.4); // часть порченых клеток пропадает
}
// Тир перекрашивает цвет ассета в tint, но белые акценты (проёмы, порог, узлы) остаются белыми: чем ближе цвет к белому, тем меньше перекраска.
vec3 recolor(vec3 c) {
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	return mix(tint.rgb * mx, c, mn / max(mx, 0.0001));
}
float dist_fade() {
	return 1.0 - smoothstep(fade_start, fade_end, v_dist);
}


varying float v_wy;
varying vec2 v_q;
varying float v_phase;
varying float v_comp;  // 1 / во сколько раз квад расширен до min_px

void vertex() {
	float w = UV2.x;
	float h = UV2.y;
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 c = VERTEX - vec3((UV.x - 0.5) * 2.0 * w, (0.5 - UV.y) * 2.0 * h, 0.0);
	v_phase = dot(c, vec3(12.9, 3.1, 7.7));
	bool dropped = keep_frac < 1.0 && fract(sin(v_phase * 3.7 + 1.3) * 43758.5453) > keep_frac;  // выпавший штрих: в конце квад уводится за пределы экрана
	float h0 = h;
	h *= 1.0 + breathe * (0.6 * sin(TIME * breathe_speed + v_phase) + 0.4 * sin(TIME * breathe_speed * 2.3 + v_phase * 1.7));
	h *= len_scale;
	vec3 wc = (MODEL_MATRIX * vec4(c, 1.0)).xyz;
	wc.y += -anchor * (h - h0) * s * sign(MODEL_MATRIX[1].y);  // длина меняется от якоря: основание стены не отрывается от пола
	if (scatter > 0.0) {
		wc.xz += (vec2(fract(sin(v_phase * 5.1 + 0.7) * 43758.5453), fract(sin(v_phase * 9.7 + 2.1) * 24634.6345)) - 0.5) * 2.0 * scatter * s;
	}
	if (lattice > 0.0) {  // колонны стоят на узлах мировой решётки по x и z, по высоте непрерывно
		wc.xz = floor(wc.xz / lattice + 0.5) * lattice;
	}
	vec3 to_cam = CAMERA_POSITION_WORLD - wc;
	to_cam.y = 0.0;
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam + vec3(0.00001, 0.0, 0.0)));
	float hw = halo > 0.0 ? halo_width : 1.0;  // квад шире для ореола; ядро во фрагменте считается в прежних метрах
	float wk = 1.0;
	v_pxk = 1.0;
	if (min_px > 0.0 || px_fade > 0.0) {  // мировой размер пикселя на дистанции штриха: 2·d / (P[1][1] · высота вьюпорта); полуширина ядра должна быть ≥ min_px / 2
		float d0 = max(-(VIEW_MATRIX * vec4(wc, 1.0)).z, 0.1);
		float px = 2.0 * d0 / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
		if (min_px > 0.0) {
			wk = max(1.0, 0.5 * min_px * px / max(w * s, 0.0001));
		}
		float nominal_px = 2.0 * w * s / px;  // ширина штриха до расширения, px
		v_pxk = mix(1.0, smoothstep(0.4, 2.0, nominal_px), px_fade);
	}
	v_comp = 1.0 / wk;
	vec3 wp = wc + right * (UV.x - 0.5) * 2.0 * w * s * hw * wk + vec3(0.0, 1.0, 0.0) * (0.5 - UV.y) * 2.0 * h * s;
	if (touch_radius > 0.0) {  // штрихи прогибаются вглубь от касания (в референсе занавес огибает руку)
		float tk = 1.0 - smoothstep(0.0, touch_radius, distance(wc, touch_pos));
		wp -= normalize(to_cam + vec3(0.00001, 0.0, 0.0)) * 0.18 * tk * s;
	}
	wp += right * sway * sin(TIME * sway_speed + v_phase * 1.3) * s;
	v_wp = wc;
	v_wy = wp.y;
	v_dist = -(VIEW_MATRIX * vec4(wp, 1.0)).z;
	v_q = vec2((UV.x - 0.5) * 2.0, (0.5 - UV.y) * 2.0);
	POSITION = dropped ? vec4(2.0, 2.0, 2.0, 1.0) : PROJECTION_MATRIX * VIEW_MATRIX * vec4(wp, 1.0);
}

void fragment() {
	float hw = halo > 0.0 ? halo_width : 1.0;
	float core = exp(-v_q.x * v_q.x * hw * hw * edge_sharp);
	float across = core;
	if (halo > 0.0) {  // ядро чуть слабее, вокруг широкий мягкий хвост (гаснет к краю квада, чтобы не было обрезки)
		across = core * 0.8 + halo * exp(-v_q.x * v_q.x * halo_sharp) * smoothstep(1.0, 0.55, abs(v_q.x));
	}
	float along = smoothstep(1.0, 1.0 - end_fade, abs(v_q.y));
	// «Бусины»: гладкая прямоугольная волна (жёсткий step давал ступеньки по длине штриха); мягкость — не меньше пикселя (fwidth) и не меньше 8% периода
	float bph = v_wy * bead_freq - TIME * bead_speed * bead_freq;
	float bf = fract(bph);
	float bw = clamp(fwidth(bph) * 1.5, 0.08, 0.5);
	float bsq = smoothstep(0.5 - bw, 0.5 + bw, bf) * (1.0 - smoothstep(1.0 - 2.0 * bw, 1.0, bf));
	float bead = 1.0 - bead_depth + bead_depth * bsq;
	float shim = 1.0 - shimmer + shimmer * (0.5 + 0.5 * sin(TIME * shimmer_speed + v_phase * 2.1));
	float wave = 1.0 - pulse + pulse * (0.5 + 0.5 * sin((v_wp.x + 0.6 * v_wp.z) * pulse_scale * 3.14159 - TIME * pulse_speed));
	float k = corrupt_k();
	vec3 col = mix(mix(COLOR.rgb, recolor(COLOR.rgb), tint_amount), corrupt_color.rgb, corrupt_mask(k));
	float boost = 1.0;
	if (touch_radius > 0.0) {  // красная горизонтальная полоса на высоте касания и мягкое пятно вокруг
		float tk = 1.0 - smoothstep(0.0, touch_radius, distance(v_wp, touch_pos));
		float band = exp(-pow((v_wy - touch_pos.y) / 0.16, 2.0));
		col = mix(col, touch_color.rgb, clamp(tk * (0.5 + 0.5 * band), 0.0, 1.0));
		boost += 2.4 * band * tk;
	}
	ALBEDO = col * glow * mix(1.0, far_gain, smoothstep(far_start, far_end, v_dist));
	ALPHA = COLOR.a * across * along * bead * wave * shim * boost * corrupt_hole(corrupt_mask(k)) * dist_fade() * intensity * v_comp * v_pxk * mix(1.0, far_dim_min, smoothstep(far_dim_start, far_dim_end, v_dist));
}
