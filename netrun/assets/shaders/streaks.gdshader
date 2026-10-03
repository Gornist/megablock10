// Штрих: вертикальная светящаяся чёрточка (основной примитив стиля, по референсам Blackwall): мягкий поперечный профиль,
// затухание к концам, «бусины» вдоль длины, которые ползут вверх. Один квадрат (2 треугольника) заменяет цепочку точек.
// Контракт с lib.py: квадрат в плоскости XZ Blender (в Godot XY) с центром c, полуширина w, полувысота h; UV0 — углы,
// UV1 = (w, h). Вертикаль — мировая ось Y, к камере разворачивается только по горизонтали (цилиндрический биллборд).
// Анимация целиком в шейдере (по гифкам референса): бегущая волна яркости вдоль стены, ползущие бусины, «дыхание» длины
// (для существ), реакция на касание: штрихи прогибаются от точки касания, по высоте касания идёт красная полоса.
// Всё медленное и неглубокое (комфорт в VR: никаких вспышек и резких движений).
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, fog_disabled;

uniform float glow : hint_range(0.0, 6.0) = 1.6;
uniform float bead_freq : hint_range(0.0, 60.0) = 14.0;   // бусин на метр
uniform float bead_depth : hint_range(0.0, 1.0) = 0.35;
uniform float bead_speed : hint_range(0.0, 2.0) = 0.25;   // бусины ползут вверх, м/с
uniform float end_fade : hint_range(0.05, 1.0) = 0.35;
uniform float edge_sharp : hint_range(1.0, 12.0) = 5.0;   // больше — тоньше ядро
uniform float pulse : hint_range(0.0, 1.0) = 0.3;         // глубина бегущей волны яркости
uniform float pulse_speed : hint_range(0.0, 3.0) = 0.7;
uniform float pulse_scale : hint_range(0.0, 8.0) = 1.6;   // волн на метр вдоль стены
uniform float breathe : hint_range(0.0, 0.4) = 0.0;       // «дыхание» длины штриха (существа)
uniform float breathe_speed : hint_range(0.0, 3.0) = 0.9;
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
	return step(cell_hash(0.0), k);
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

void vertex() {
	float w = UV2.x;
	float h = UV2.y;
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 c = VERTEX - vec3((UV.x - 0.5) * 2.0 * w, (0.5 - UV.y) * 2.0 * h, 0.0);
	v_phase = dot(c, vec3(12.9, 3.1, 7.7));
	h *= 1.0 + breathe * sin(TIME * breathe_speed + v_phase);
	vec3 wc = (MODEL_MATRIX * vec4(c, 1.0)).xyz;
	vec3 to_cam = CAMERA_POSITION_WORLD - wc;
	to_cam.y = 0.0;
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam + vec3(0.00001, 0.0, 0.0)));
	vec3 wp = wc + right * (UV.x - 0.5) * 2.0 * w * s + vec3(0.0, 1.0, 0.0) * (0.5 - UV.y) * 2.0 * h * s;
	if (touch_radius > 0.0) {  // штрихи прогибаются вглубь от касания (в референсе занавес огибает руку)
		float tk = 1.0 - smoothstep(0.0, touch_radius, distance(wc, touch_pos));
		wp -= normalize(to_cam + vec3(0.00001, 0.0, 0.0)) * 0.18 * tk * s;
	}
	v_wp = wc;
	v_wy = wp.y;
	v_dist = -(VIEW_MATRIX * vec4(wp, 1.0)).z;
	v_q = vec2((UV.x - 0.5) * 2.0, (0.5 - UV.y) * 2.0);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wp, 1.0);
}

void fragment() {
	float across = exp(-v_q.x * v_q.x * edge_sharp);
	float along = smoothstep(1.0, 1.0 - end_fade, abs(v_q.y));
	float bead = 1.0 - bead_depth + bead_depth * step(0.5, fract(v_wy * bead_freq - TIME * bead_speed * bead_freq));
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
	ALBEDO = col * glow;
	ALPHA = COLOR.a * across * along * bead * wave * boost * corrupt_hole(corrupt_mask(k)) * dist_fade() * intensity;
}
