// Эталон V11: точка строки скана — биллборд мирового размера (MultiMesh), непрозрачный диск с discard.
// INSTANCE_CUSTOM: x — номер строки, y — шаг строк (м), z — направление шага (0 — по Y, грани; 1 — по Z, пол; 3 — без прореживания),
// w — диаметр точки (м). COLOR.rgb — цвет точки (линейный) с освещённостью и разбросом, посчитанными при генерации.
// Прореживание строк по экрану: строки, сошедшиеся ближе min_row_px, гаснут по двоичному порядку (каждая вторая, четвёртая…) —
// вдали сохраняется пустота между строками, а не слипшаяся плашка.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, skip_vertex_transform;

#include "res://assets/look_v11/scan_common.gdshaderinc"

void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	if (dot(d, d) > 1.0) discard;
	vec3 c = v_col;
	if (rim_gain > 0.0) c = mix(v_col, rim_col * rim_gain, v_rim);
	else c = v_col * (1.0 + v_rim);  // кромка мира (world_rim), у пола и рамки v_rim = 0
	ALBEDO = mix(void_col, c, clamp(v_k, 0.0, 1.0));
}
