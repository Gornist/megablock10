// Признаки объёмного дисплея (B4, 15.11): бегущая развёртка и ступенчатая яркость. Включать из шейдеров облаков и точек (particles_body, points, volume_cloud);
// в умолчании (sweep_gain = 0, lum_steps = 0) обе функции тождественны. Фазу развёртки задаёт клиент с CPU (NodeView, ручка sweep_period), а не TIME:
// TIME в Godot сбрасывается раз в час, и по шву развёртка прыгала бы. fwidth от fract не брать: на шве даёт скачок.

global uniform float sweep_phase;          // фаза развёртки 0…1 (глобальный uniform проекта, project.godot [shader_globals])
uniform float sweep_gain : hint_range(0.0, 0.5) = 0.0;
uniform vec3 sweep_dir = vec3(1.0, 0.0, 0.0);
uniform float sweep_span = 6.0;            // м, длина прохода
uniform float sweep_decay = 0.15;          // доля прохода, послесвечение
uniform int lum_steps : hint_range(0, 16) = 0;

// Множитель яркости от развёртки в мировой точке wp: фронт бежит вдоль sweep_dir, за ним послесвечение; не выше 1,25.
float sweep_mul(vec3 wp) {
	if (sweep_gain <= 0.0) {
		return 1.0;
	}
	float s = fract(dot(wp, sweep_dir) / sweep_span - sweep_phase);
	return min(1.0 + sweep_gain * exp(-s / max(sweep_decay, 1e-3)), 1.25);
}

// Яркость (максимум каналов) округляется до lum_steps ступеней, оттенок сохраняется.
vec3 quant_lum(vec3 c) {
	if (lum_steps <= 0) {
		return c;
	}
	float l = max(c.r, max(c.g, c.b));
	if (l <= 1e-4) {
		return c;
	}
	float n = float(lum_steps);
	return c * (floor(l * n + 0.5) / n) / l;
}
