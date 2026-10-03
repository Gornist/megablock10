// Облако точек: каждая точка — квадрат из 4 вершин, всегда обращённый к камере, круглая мягкая точка.
// Контракт с lib.py (Blender): квадрат лежит в плоскости XZ Blender (в Godot — XY) с центром c и полуразмером h;
// UV0 — углы квадрата, UV1.x = h. Центр восстанавливаем вычитанием смещения угла из позиции вершины.
// Мерцание медленное и неглубокое (комфорт в VR); цвет и яркость — из цвета вершин.
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, fog_disabled;

uniform float glow : hint_range(0.0, 6.0) = 2.0;
uniform float twinkle : hint_range(0.0, 0.5) = 0.15;
uniform float twinkle_speed : hint_range(0.0, 3.0) = 0.6;
uniform vec4 tint : source_color = vec4(1.0);
uniform float tint_amount : hint_range(0.0, 1.0) = 0.0;

varying float v_phase;

void vertex() {
	float h = UV2.x;
	vec3 c = VERTEX - vec3((UV.x - 0.5) * 2.0 * h, (0.5 - UV.y) * 2.0 * h, 0.0);
	v_phase = dot(c, vec3(12.9, 78.2, 37.7));
	vec4 mv = MODELVIEW_MATRIX * vec4(c, 1.0);
	mv.xy += vec2(UV.x - 0.5, 0.5 - UV.y) * 2.0 * h;
	POSITION = PROJECTION_MATRIX * mv;
}

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float soft = smoothstep(1.0, 0.25, d);
	float tw = 1.0 - twinkle + twinkle * sin(TIME * twinkle_speed + v_phase);
	ALBEDO = mix(COLOR.rgb, tint.rgb, tint_amount) * glow;
	ALPHA = soft * COLOR.a * tw;
}
