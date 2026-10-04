// Общая часть шейдеров облаков из точек: рука (hand_particles.gdshader, видна всегда) и чужое тело (body_particles.gdshader, с проверкой глубины).
// Данные экземпляра: COLOR — цвет; INSTANCE_CUSTOM: x — полуразмер, м; y — фаза 0…1 (волна света); z — вид (0 точка, 1 искра); w — яркость 0…1.

uniform float glow : hint_range(0.0, 6.0) = 1.6;
uniform float lattice : hint_range(0.0, 0.05) = 0.006;         // шаг решётки, м (0 — выкл.)
uniform float wave_speed : hint_range(0.0, 4.0) = 0.9;         // бегущая от запястья к кончикам волна света, циклов в секунду
uniform float wave_depth : hint_range(0.0, 1.0) = 0.6;
uniform float twinkle : hint_range(0.0, 0.5) = 0.2;
uniform float spark_rise : hint_range(0.0, 0.2) = 0.07;        // на сколько искра поднимается над кончиком за цикл, м
uniform float spark_half_len : hint_range(0.0, 0.05) = 0.013;  // полудлина искры, м
uniform float intensity : hint_range(0.0, 4.0) = 1.0;

varying vec3 v_col;
varying float v_alpha;
varying float v_kind;
varying float v_fade;

void vertex() {
	float size = INSTANCE_CUSTOM.x;
	float phase = INSTANCE_CUSTOM.y;
	float kind = INSTANCE_CUSTOM.z;
	float weight = INSTANCE_CUSTOM.w;
	vec3 w = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float fade = 1.0;
	if (kind > 0.5) {
		float rise = fract(TIME * 0.55 + phase * 7.0);  // искра поднимается и гаснет, у каждой своя фаза
		w.y += rise * spark_rise;
		fade = sin(rise * 3.14159);
	} else if (lattice > 0.0) {
		w = floor(w / lattice + 0.5) * lattice;
	}
	float wave = 0.5 + 0.5 * sin(6.28318 * (TIME * wave_speed - phase * 1.4));
	float tw = 1.0 - twinkle + twinkle * sin(TIME * 2.3 + phase * 40.0 + float(INSTANCE_ID) * 1.7);
	v_alpha = weight * mix(1.0 - wave_depth, 1.0, wave) * tw * fade * intensity;
	v_col = COLOR.rgb;
	v_kind = kind;
	vec4 mv = VIEW_MATRIX * vec4(w, 1.0);
	vec2 q = vec2(UV.x - 0.5, 0.5 - UV.y) * 2.0;
	if (kind > 0.5) {
		vec2 up = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xy;  // вертикаль мира в плоскости экрана: штрих всегда стоит вертикально
		mv.xy += vec2(q.x * size, 0.0) + up * q.y * spark_half_len;
	} else {
		mv.xy += q * size;
	}
	POSITION = PROJECTION_MATRIX * mv;
}

void fragment() {
	vec2 q = (UV - vec2(0.5)) * 2.0;
	float soft;
	if (v_kind > 0.5) {
		soft = smoothstep(1.0, 0.0, abs(q.x)) * (1.0 - q.y * q.y);
	} else {
		soft = smoothstep(1.0, 0.25, length(q));
	}
	ALBEDO = v_col * glow;
	ALPHA = clamp(soft * v_alpha, 0.0, 1.0);
}
