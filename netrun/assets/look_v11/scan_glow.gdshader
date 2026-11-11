// Эталон V11: ореол точки скана — тот же экземпляр, квад в size_mul раз больше, мягкое пятно аддитивно без записи глубины.
// Точка читается светящейся (ядро + свечение вокруг), а не крапом краски на грани. На Pico — дорого (overdraw ×size_mul²): см. README.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform;

uniform float glow = 0.35;

#include "res://assets/look_v11/scan_common.gdshaderinc"

void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float r2 = dot(d, d);
	if (r2 > 1.0) discard;
	vec3 c = v_col;
	if (rim_gain > 0.0) c = mix(v_col, rim_col * rim_gain, v_rim);
	else c = v_col * (1.0 + v_rim);  // кромка мира (world_rim), у пола и рамки v_rim = 0
	ALBEDO = c * exp(-r2 * 4.0) * clamp(v_k, 0.0, 1.0) * glow;
}
