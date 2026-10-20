// Звёзды фона (BackdropDome): мелкие квады-билборды на фиксированных МИРОВЫХ позициях вокруг комнаты (≈55 м), без неба в пикселе (atan/acos/текстура на весь экран стоили на Pico
// +2 мс, 20.10) и без привязки к виду: позиция звезды — координата мира, поэтому она стоит на месте при любом повороте головы, рига и сцены.
// Аддитивный свет поверх прозрачного фона вида (blend_premul_alpha, ALPHA = 0 — альфа кадра не трогается: слой деки позади виден). Тест глубины включён, запись выключена:
// пол, колонны и всё ближе закрывают звёзды. Размер — угловой (star_angle, рад): звезда не мельче ~1 px на любой дистанции.
shader_type spatial;
render_mode unshaded, blend_premul_alpha, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

uniform vec3 star_color : source_color = vec3(0.45, 0.85, 0.95);
uniform float star_gain : hint_range(0.0, 4.0) = 1.0;       // ручка `backdrop_dust`
uniform float star_angle : hint_range(0.0005, 0.01) = 0.0016;   // угловой радиус звезды, рад (на Pico ≈ 860 px/рад → ≈1,4 px)

varying float v_b;

void vertex() {
	vec3 c = (VIEW_MATRIX * MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;   // центр звезды в виде
	vec3 p = c + vec3(VERTEX.xy * 2.0 * star_angle * length(c), 0.0);        // квад размера 1 → радиус star_angle·дистанция, лицом к глазу
	POSITION = PROJECTION_MATRIX * vec4(p, 1.0);
	v_b = INSTANCE_CUSTOM.x;
}

void fragment() {
	float soft = smoothstep(1.0, 0.15, length(UV * 2.0 - 1.0));
	ALBEDO = star_color * star_gain * v_b * soft;
	ALPHA = 0.0;
}
