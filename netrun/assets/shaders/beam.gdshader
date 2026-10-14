// Луч Soft ICE (меши `*_beam` у датчика и `*_fan` у маяка; docs/gamedesign/ice.md §5, levels.md §9): тонкая светящаяся полоса или веер на полу.
// Геометрию и длину задаёт Godot (масштаб узла `Beam` вдоль +Y Blender = −Z Godot); здесь — материал и три состояния датчика.
// UV: u — вдоль длины 0…1 (у веера — радиус от вершины), v — поперёк 0…1 (у веера — угол от края до края). Цвета — из AssetMaterials.LAYERS
// (beam_on, beam_off, beam_flash), параметры состояния — set_param(root, "state" | "flash", …).
// Аддитивный, без записи глубины и без чтения буфера глубины (как skirt): в слоях перерисовки один квад на луч.
// Комфорт (VR): мигание — мягкая синусоида 1,25 Гц, не стробоскоп; вспышка срабатывания — одиночный импульс, длину задаёт игра.
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, fog_disabled;

uniform vec4 on_color : source_color = vec4(1.0, 0.48, 0.42, 1.0);
uniform vec4 off_color : source_color = vec4(0.18, 0.42, 0.47, 1.0);
uniform vec4 flash_color : source_color = vec4(0.85, 0.97, 1.0, 1.0);
// 0 — погашен (тусклая линия: путь виден, пройти можно), 1 — горит, 2 — мигает за такт до включения.
uniform float state : hint_range(0.0, 2.0) = 1.0;
// 0…1: вспышка при срабатывании (поверх состояния).
uniform float flash : hint_range(0.0, 1.0) = 0.0;
// 1 — веер маяка (радиальное затухание), 0 — полоса датчика (мягкие концы и края).
uniform float fan : hint_range(0.0, 1.0) = 0.0;
uniform float glow : hint_range(0.0, 4.0) = 1.0;
uniform float fade_start = 60.0;
uniform float fade_end = 90.0;
uniform float intensity = 1.0;

varying float v_dist;

void vertex() {
	v_dist = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}

void fragment() {
	float u = UV.x;
	float across = abs(UV.y * 2.0 - 1.0);   // 0 по оси, 1 на краю
	float shape;
	if (fan > 0.5) {
		shape = pow(1.0 - u, 1.1) * (1.0 - across * across);
	} else {
		shape = smoothstep(0.0, 0.04, u) * (1.0 - smoothstep(0.92, 1.0, u)) * (1.0 - across * across);
	}
	float blink = 0.15 + 0.85 * smoothstep(-0.2, 0.6, sin(TIME * 7.85));
	float level = state < 0.5 ? 0.22 : (state < 1.5 ? 1.0 : blink);
	vec3 base = state < 0.5 ? off_color.rgb : on_color.rgb;
	vec3 col = mix(base, flash_color.rgb, flash);
	float fade = 1.0 - smoothstep(fade_start, fade_end, v_dist);
	ALBEDO = col * glow;
	ALPHA = clamp(shape * COLOR.a * mix(level, 1.6, flash) * fade * intensity, 0.0, 1.0);
}
