// Ореол-«капля свечения» маяка предмета (меш `beacon_halo` в узле Beacon у шарда и токена): один квад 0,5×0,5 м вокруг предмета, круглый, очень мягкий.
// Биллборд по Y, как у штрихов (поворот только вокруг вертикали, к камере боком), радиальный гауссов профиль, гаснет к краю квада без обрезки.
// Аддитивный, без освещения, без записи глубины и без чтения буфера глубины (без depth-fade, без постобработки): один слой прозрачности.
// Контракт с lib.py/props.py: квад в плоскости XZ Blender (в Godot XY), UV0 — углы, UV1 = (r, 1−r) → в шейдере UV2 = (полуразмер, полуразмер); по ним находим центр квада.
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, fog_disabled;

uniform float glow : hint_range(0.0, 4.0) = 1.0;
uniform float halo_alpha : hint_range(0.0, 1.0) = 0.17;  // непрозрачность в центре; «очень мягкий» — слабая дымка, а не диск
uniform float falloff : hint_range(0.5, 8.0) = 5.0;       // крутизна: больше — ореол уже
uniform float breathe : hint_range(0.0, 0.5) = 0.12;      // медленное «дыхание» яркости (комфорт в VR: без вспышек)
uniform float breathe_speed : hint_range(0.0, 3.0) = 0.8;
uniform vec4 tint : source_color = vec4(1.0);
uniform float tint_amount : hint_range(0.0, 1.0) = 0.0;
uniform float fade_start = 60.0;
uniform float fade_end = 90.0;
uniform float intensity = 1.0;

varying vec2 v_q;
varying float v_dist;

void vertex() {
	float r = UV2.x;
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 c = VERTEX - vec3((UV.x - 0.5) * 2.0 * r, (0.5 - UV.y) * 2.0 * r, 0.0);
	vec3 wc = (MODEL_MATRIX * vec4(c, 1.0)).xyz;
	vec3 to_cam = CAMERA_POSITION_WORLD - wc;
	to_cam.y = 0.0;
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), to_cam + vec3(0.00001, 0.0, 0.0)));
	vec3 wp = wc + right * (UV.x - 0.5) * 2.0 * r * s + vec3(0.0, 1.0, 0.0) * (0.5 - UV.y) * 2.0 * r * s;
	v_q = vec2((UV.x - 0.5) * 2.0, (0.5 - UV.y) * 2.0);
	v_dist = -(VIEW_MATRIX * vec4(wp, 1.0)).z;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wp, 1.0);
}

vec3 recolor(vec3 c) {
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	return mix(tint.rgb * mx, c, mn / max(mx, 0.0001));
}

void fragment() {
	float d2 = dot(v_q, v_q);
	float k = exp(-d2 * falloff) * smoothstep(1.0, 0.55, sqrt(d2));
	float br = 1.0 - breathe + breathe * (0.5 + 0.5 * sin(TIME * breathe_speed));
	float fade = 1.0 - smoothstep(fade_start, fade_end, v_dist);
	ALBEDO = mix(COLOR.rgb, recolor(COLOR.rgb), tint_amount) * glow;
	ALPHA = COLOR.a * halo_alpha * k * br * fade * intensity;
}
