// Общее для точки скана (scan_point) и её ореола (scan_glow): параметры и вершинный шейдер. См. scan_point.gdshader.
uniform vec3 void_col : source_color = vec3(0.0392, 0.0471, 0.0549);
uniform float min_px = 1.6;       // точка на экране не меньше, px; меньше — гасим яркость
uniform float min_row_px = 3.5;   // строки ближе — прореживаем
uniform float fade_near = 3.0;    // затухание к пустоте по глубине, м
uniform float fade_far = 15.0;
uniform float fade_min = 0.0;     // остаток яркости у fade_far
uniform float gain = 1.0;
uniform float vp_h = 720.0;      // высота кадра, px (VIEWPORT_SIZE в вершинном шейдере Mobile — ноль)

uniform float pt_step = 0.0;     // шаг точек в строке, м (0 — не прореживать в строке)
uniform float min_dot_px = 2.6;  // точки в строке ближе — прореживаем
uniform float world_rim = 0.0;   // мир: усиление яркости на кромке (взгляд вскользь), 0 — нет
uniform float size_mul = 1.0;    // ореол: квад во столько раз больше точки
uniform float rim_gain = 0.0;    // > 0 — фигура: COLOR = тёмное тело, к кромке — rim_col
uniform vec3 rim_col : source_color = vec3(0.773, 0.220, 0.294);

varying vec3 v_col;
varying float v_k;
varying float v_rim;

void vertex() {
	vec4 cd = INSTANCE_CUSTOM;
	v_rim = 0.0;
	vec3 center = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 vc = (VIEW_MATRIX * vec4(center, 1.0)).xyz;
	float depth = max(-vc.z, 0.05);
	float ppm = abs(PROJECTION_MATRIX[1][1]) * vp_h * 0.5 / depth;  // в Vulkan [1][1] < 0
	float size = cd.w;
	float k = 1.0;
	float spx = size * ppm;
	if (spx < min_px) {
		k = clamp(spx / min_px, 0.25, 1.0);
		size = min_px / ppm;
	}
	float lf = 1.0;
	if (cd.z < 2.5) {
		vec3 sdir = cd.z < 0.5 ? vec3(0.0, 1.0, 0.0) : (cd.z < 1.5 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0));
		vec3 vd = normalize(center - CAMERA_POSITION_WORLD);
		float c = dot(vd, sdir);
		float rpx = cd.y * ppm * sqrt(max(1.0 - c * c, 0.0));
		float lvl = log2(max(min_row_px / max(rpx, 1e-4), 1.0));
		int r = int(cd.x + 0.5);
		int tz = 0;
		if (r == 0) {
			tz = 16;
		} else {
			int x = r;
			for (int i = 0; i < 16; i++) {
				if ((x & 1) != 0) break;
				x = x >> 1;
				tz++;
			}
		}
		float fl = floor(lvl);
		if (float(tz) < fl) lf = 0.0;
		else if (float(tz) < fl + 1.0) lf = 1.0 - fract(lvl);
	}
	// прореживание внутри строки: точки, сошедшиеся ближе min_dot_px, гаснут по своему случайному порогу (COLOR.a) — строка остаётся пунктиром
	if (pt_step > 0.0) {
		float dens = clamp(pt_step * ppm / min_dot_px, 0.0, 1.0);
		lf *= smoothstep(COLOR.a - 0.08, COLOR.a, dens);
	}
	if (rim_gain > 0.0) {  // фигура: нормаль точки лежит в базисе экземпляра, кромка светлее (френель)
		vec3 nrm = normalize(MODEL_MATRIX[0].xyz);
		float fr = 1.0 - abs(dot(nrm, normalize(CAMERA_POSITION_WORLD - center)));
		v_rim = pow(fr, 2.0);
		lf *= 1.0 - smoothstep(0.55, 0.95, fr) * step(0.45, COLOR.a);  // у кромки часть точек гаснет — край рассыпается
	}
	if (world_rim > 0.0 && cd.z < 0.5) {  // мир, только грани (у пола вскользь — весь дальний пол): кромка светлее там, где смотрим на оболочку вскользь — подсвеченные края форм, как у камней CP2077
		vec3 nrm = normalize(MODEL_MATRIX[0].xyz);
		float fr = 1.0 - abs(dot(nrm, normalize(CAMERA_POSITION_WORLD - center)));
		v_rim = world_rim * pow(fr, 3.0);
	}
	float fade = mix(1.0, fade_min, smoothstep(fade_near, fade_far, depth));
	v_k = k * lf * fade * gain;
	v_col = COLOR.rgb;
	if (lf <= 0.001) {
		VERTEX = vec3(0.0, 0.0, 10.0);  // за камерой — отсечётся
	} else {
		vec3 wp = center + (INV_VIEW_MATRIX[0].xyz * VERTEX.x + INV_VIEW_MATRIX[1].xyz * VERTEX.y) * size * size_mul;
		VERTEX = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
	}
}
