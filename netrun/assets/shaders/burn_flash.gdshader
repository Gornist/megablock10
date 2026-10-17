shader_type spatial;
render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled;
// Вспышка ожога по краям зрения (П6-6 (г), владелец на П6: «ни смены цвета, ни логова»). Квад на камере в 0,24 м (DangerCue), угол от оси взгляда — из VERTEX.
// Цвет — слои burn_flash / burn_flash_hot палитры (AssetMaterials), уровень — uniform strength 0…1 (Godot: линейный спад за burn_flash_sec).
// Форма: слабая красная вуаль на весь взгляд (смена цвета заметна и в центре, но цель не закрыта), край — гуще и горячее, у самой границы — яркий обод.
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(1.0, 0.12, 0.24, 1.0);
uniform vec4 hot : source_color = vec4(1.0, 0.48, 0.42, 1.0);
uniform float half_fov = 0.95;       // половина поля зрения, рад (очки Pico ≈ 0,95; плоский клиент — по vfov)
uniform float inner = 0.45;          // доля half_fov, с которой начинается красный край
uniform float wash = 0.07;          // вуаль на весь взгляд (доля strength)
uniform float rim_width = 0.14;      // доля half_fov под обод

void fragment() {
	float ang = acos(clamp(dot(normalize(VERTEX), vec3(0.0, 0.0, -1.0)), -1.0, 1.0));
	float t = clamp(ang / half_fov, 0.0, 1.5);
	float edge = smoothstep(inner, 1.0, t);
	float rim = smoothstep(1.0 - rim_width, 1.0, t);
	float body = max(wash, pow(edge, 2.2) * 0.8);
	vec3 col = mix(tint.rgb, hot.rgb, rim);
	ALBEDO = col;
	ALPHA = clamp(max(body, rim * 0.9) * strength, 0.0, 1.0);
}
