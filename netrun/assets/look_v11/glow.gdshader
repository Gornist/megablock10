// Эталон V11: аддитивные вещи без записи глубины — ореол (mode 0: мягкое пятно, биллборд) и световой лист портала
// (mode 1: вертикальные потёки, плоскость в мире).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform int mode = 0;
uniform vec3 col : source_color = vec3(0.157, 0.675, 0.682);
uniform vec3 core : source_color = vec3(0.463, 0.776, 0.773);
uniform float energy = 0.3;
uniform float streaks = 70.0;   // потёков на ширину листа

float h(float x) { return fract(sin(x * 12.9898) * 43758.5453); }

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	if (mode == 0) {
		float r2 = dot(p, p);
		float g = exp(-r2 * 5.0) * (1.0 - smoothstep(0.7, 1.0, sqrt(r2)));
		ALBEDO = col * g * energy;
	} else {
		float x = UV.x * streaks;
		float i = floor(x);
		float f = fract(x);
		float w = 0.25 + 0.35 * h(i);
		float line = smoothstep(w, 0.0, abs(f - 0.5));
		float lvl = 0.35 + 0.65 * h(i + 7.0);
		// сегменты по высоте: каждый потёк — столбик коротких отрезков
		float seg = step(0.25, fract(UV.y * (6.0 + 10.0 * h(i + 3.0)) + h(i + 5.0)));
		float edge = smoothstep(0.0, 0.12, UV.x) * smoothstep(0.0, 0.12, 1.0 - UV.x) * smoothstep(0.0, 0.08, UV.y) * smoothstep(0.0, 0.05, 1.0 - UV.y);
		float v = (0.35 + 0.65 * line * lvl * seg) * edge;
		ALBEDO = mix(col, core, line * lvl) * v * energy;
	}
}
