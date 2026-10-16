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
uniform float min_angle : hint_range(0.0, 0.01) = 0.0;         // наименьший угловой размер точки, рад: далёкие точки не мельче ~2 пикселей (чужое тело; у своих рук 0)

// Глитч-спрайт (GlitchSprite): вместо круглой точки — анимированное блочное пятно, у каждой частицы своя фаза. glitch_mix = 0 — прежние круглые точки.
uniform sampler2D glitch_tex : filter_linear_mipmap, repeat_disable;
uniform float glitch_mix : hint_range(0.0, 1.0) = 0.0;          // 0 — выкл., 1 — все точки (не искры) рисуются спрайтом
uniform float glitch_fps : hint_range(1.0, 30.0) = 12.0;
uniform float glitch_scale : hint_range(0.2, 4.0) = 1.0;        // полуширина квада в полуразмерах точки; высота вдвое больше (ячейка 1:2)
uniform vec2 glitch_cells = vec2(8.0, 4.0);                     // столбцов и строк атласа

uniform float facing_fade : hint_range(0.0, 1.0) = 0.0;       // 1 — гасить точки, обращённые от камеры (голова: лицо спереди не просвечивает затылком); 0 — не гасить (руки)
uniform vec3 facing_center = vec3(0.0);                          // центр объёма в мировых координатах, от него считается «наружу»; задаёт узел каждый кадр

// Дыхание: всё облако вдыхает единой волной, вдох — на тике хода. Фазу такта (0 — тик, 1 — следующий тик) каждый кадр задаёт клиент; сам шейдер времени не ведёт.
// Волна чуть бежит по пространству (breath_spread), поэтому соседние объекты вдыхают с лёгким сдвигом, а не хлопают разом. breath_depth = 0 — выкл. (руки, тело).
uniform float breath_depth : hint_range(0.0, 1.0) = 0.0;
uniform float breath_phase : hint_range(0.0, 1.0) = 0.0;
uniform float breath_spread : hint_range(0.0, 0.5) = 0.08;    // сдвиг фазы волны, долей такта на метр вдоль (x, y, z) ≈ (1, 0.5, 0.7)

// Отклик на приближение (рука, аватар): до четырёх источников, xyz — мир, w — радиус влияния, м (0 — источник выключен). Без состояния и следа: частицы
// отвечают положению источника в этом кадре — рядом крупнее, ярче, теплее по цвету и чуть расходятся от источника, источник ушёл — всё как было.
uniform vec4 touch_a = vec4(0.0);
uniform vec4 touch_b = vec4(0.0);
uniform vec4 touch_c = vec4(0.0);
uniform vec4 touch_d = vec4(0.0);
uniform float touch_gain : hint_range(0.0, 4.0) = 1.2;        // прибавка яркости у самого источника
uniform float touch_grow : hint_range(0.0, 3.0) = 0.8;        // прибавка размера у самого источника
uniform float touch_push : hint_range(0.0, 0.1) = 0.025;      // на сколько частица расходится от источника, м
uniform vec3 touch_color = vec3(0.85, 0.98, 1.0);             // цвет, к которому частицы уходят у источника (по умолчанию ice_white)

varying vec3 v_col;
varying float v_alpha;
varying float v_kind;
varying float v_fade;
varying flat float v_frame;

// Близость к источнику 0…1 (1 — в нём, 0 — на радиусе и дальше) и вклад в сдвиг.
float touch_near(vec4 t, vec3 p, inout vec3 push) {
	if (t.w <= 0.0) {
		return 0.0;
	}
	vec3 d = p - t.xyz;
	float k = 1.0 - smoothstep(0.0, t.w, length(d));
	push += normalize(d + vec3(0.0, 0.0001, 0.0)) * k;
	return k;
}

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
	float facing = 1.0;
	if (facing_fade > 0.5) {
		vec3 out_dir = normalize(w - facing_center + vec3(0.0, 0.0, 0.0001));
		float d = dot(out_dir, normalize(CAMERA_POSITION_WORLD - facing_center));
		facing = mix(0.12, 1.0, smoothstep(-0.15, 0.4, d));  // с обратной стороны точка остаётся бледной
	}
	float lift = 1.0;   // множитель яркости от дыхания и отклика
	float swell = 1.0;  // множитель размера
	vec3 tint = COLOR.rgb;
	if (breath_depth > 0.0) {
		float ph = breath_phase - breath_spread * dot(w, vec3(1.0, 0.5, 0.7));
		float b = 0.5 + 0.5 * cos(6.28318 * ph);   // пик — на тике, спад к концу такта
		b *= b;                                       // вдох короткий и резкий, выдох долгий
		lift *= mix(1.0 - 0.45 * breath_depth, 1.0 + 0.35 * breath_depth, b);
		swell *= 1.0 + 0.25 * breath_depth * b;
	}
	if (touch_a.w + touch_b.w + touch_c.w + touch_d.w > 0.0) {
		vec3 push = vec3(0.0);
		float k = touch_near(touch_a, w, push);
		k = max(k, touch_near(touch_b, w, push));
		k = max(k, touch_near(touch_c, w, push));
		k = max(k, touch_near(touch_d, w, push));
		w += push * touch_push;
		lift *= 1.0 + touch_gain * k;
		swell *= 1.0 + touch_grow * k;
		tint = mix(tint, touch_color, 0.6 * k);
	}
	size *= swell;
	v_alpha = weight * mix(1.0 - wave_depth, 1.0, wave) * tw * fade * intensity * facing * lift;
	v_col = tint;
	v_kind = kind;
	vec4 mv = VIEW_MATRIX * vec4(w, 1.0);
	float grown = max(size, length(mv.xyz) * min_angle);
	float spark_scale = grown / max(size, 0.0001);
	size = grown;
	vec2 q = vec2(UV.x - 0.5, 0.5 - UV.y) * 2.0;
	if (kind > 0.5) {
		vec2 up = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xy;  // вертикаль мира в плоскости экрана: штрих всегда стоит вертикально
		mv.xy += vec2(q.x * size, 0.0) + up * q.y * spark_half_len * spark_scale;
	} else if (glitch_mix > 0.5) {
		// глитч-блок: квад 1:2, стоит вертикально в мире; кадр — по времени и случайной фазе частицы, чтобы рука не мигала в такт
		vec2 up = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xy;
		float ul = length(up);
		up = ul > 0.05 ? up / ul : vec2(0.0, 1.0);
		float k = size * glitch_scale;
		mv.xy += vec2(q.x * k, 0.0) + up * q.y * k * 2.0;
		float n = glitch_cells.x * glitch_cells.y;
		float rnd = fract(sin(float(INSTANCE_ID) * 12.9898 + phase * 78.233) * 43758.5453);
		v_frame = floor(mod(TIME * glitch_fps + rnd * n, n));
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
	} else if (glitch_mix > 0.5) {
		vec2 cell = vec2(mod(v_frame, glitch_cells.x), floor(v_frame / glitch_cells.x));
		soft = texture(glitch_tex, (cell + UV) / glitch_cells).r;
	} else {
		soft = smoothstep(1.0, 0.25, length(q));
	}
	ALBEDO = v_col * glow;
	ALPHA = clamp(soft * v_alpha, 0.0, 1.0);
}
