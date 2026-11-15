// Строки скана на непрозрачной грани (B3, 15.11; код — ядро ревью раунда 3): излучатель поверх «пустоты», ALPHA не пишется.
// Три стадии с ОДИНАКОВЫМ средним: точки у ног → линия строки → ровный тон. Среднее не подгоняется константой:
//   mean_cov = present · (2·radius)² / (dot_step · row_step)
// при условии radius + jitter·dot_step ≤ 0,5·dot_step − 0,001 (квадрат не вылезает из своего слота; AssetMaterials._sanitize_knobs держит его).
// Пик линии L = present · 2·radius / dot_step ≤ 1, иначе клип съест энергию (шов).
// Свет, дыхание, рука, тревога — уже внутри point_rgb (множители ЦВЕТА излучателя); present — только плотность (пропуски, рука как плотность).
// Менять одно без другого нельзя: разойдётся среднее. Одна ячейка на пиксель, один целочисленный хэш, точный бокс-фильтр cov1d (интеграл равен 2h при любом fw).
// Производные (dpdx, dpdy) берёт вызывающий ДО любых веток: внутри неоднородного if они не определены. Ветки по scan_debug — по uniform, однородные.

uniform float row_step : hint_range(0.02, 0.2) = 0.04;       // шаг строк, м; кратно AssetMaterials.ENTITY_LATTICE (4 см), иначе в кадре два разных «дисплея»
uniform float dot_step : hint_range(0.02, 0.2) = 0.07;       // шаг точек вдоль строки, м
uniform float row_radius : hint_range(0.001, 0.03) = 0.009;  // полусторона квадратного излучателя, м
uniform float row_jitter : hint_range(0.0, 0.45) = 0.25;     // разброс центра точки внутри слота, доли шага точек
uniform float row_gap : hint_range(0.0, 0.8) = 0.12;         // доля пропущенных точек (используется вызывающим: present = 1 − row_gap)
uniform vec3 pattern_origin = vec3(0.0);                     // начало узора = origin комнаты, не камера (иначе узор плывёт при ходьбе); при рецентре трекинга двигается вместе с комнатой
uniform float scan_debug = 0.0;                               // 1 — пиксельный размер строки (серый = 4 px), 2 — только тон, 3 — только точки

uint pcg_hash(uint x) {
	x = x * 747796405u + 2891336453u;
	uint w = ((x >> ((x >> 28u) + 4u)) ^ x) * 277803737u;
	return (w >> 22u) ^ w;
}

// Хэш 0…1 по номерам ячейки (целые, относительно pattern_origin): точность не зависит от больших мировых координат.
float scan_hash(ivec2 cell) {
	uint h = pcg_hash(uint(cell.x) + pcg_hash(uint(cell.y) + 0x9e3779b9u));
	return float(h >> 8u) * (1.0 / 16777216.0);
}

// Бокс-фильтр индикатора [-h, h] шириной окна 2·fw вокруг d. Интеграл по d равен 2h при любом fw > 0.
float cov1d(float d, float h, float fw) {
	fw = max(fw, 1e-5);
	return clamp((min(d + fw, h) - max(d - fw, -h)) / (2.0 * fw), 0.0, 1.0);
}

// Среднее покрытие узора (доля площади, занятая излучателями): та же формула, что в начале файла.
float scan_mean_cov(float present_prob) {
	float present = clamp(present_prob, 0.0, 1.0);
	return clamp(present * (4.0 * row_radius * row_radius) / max(dot_step * row_step, 1e-8), 0.0, 1.0);
}

vec3 scan_rows(vec3 wp, vec3 dpdx, vec3 dpdy, vec3 row_dir, vec3 phase_dir, vec3 point_rgb, vec3 void_rgb, float present_prob) {
	vec3 p = wp - pattern_origin;
	float along = dot(p, row_dir);
	float phase = dot(p, phase_dir);
	float fw_along = 0.5 * length(vec2(dot(dpdx, row_dir), dot(dpdy, row_dir)));
	float fw_phase = 0.5 * length(vec2(dot(dpdx, phase_dir), dot(dpdy, phase_dir)));
	float grad_ok = step(1e-7, fw_phase + fw_along);

	float row_px = row_step / max(fw_phase * 2.0, 1e-5);
	float dot_px = (2.0 * row_radius) / max(fw_along * 2.0, 1e-5);
	float slot_px = dot_step / max(fw_along * 2.0, 1e-5);
	if (scan_debug > 0.5 && scan_debug < 1.5) {
		return vec3(clamp(row_px / 4.0, 0.0, 1.0));
	}

	float present = clamp(present_prob, 0.0, 1.0);
	float mean_cov = scan_mean_cov(present);
	vec3 col_mean = mix(void_rgb, point_rgb, mean_cov);
	if (scan_debug > 1.5 && scan_debug < 2.5) {
		return col_mean;
	}

	// Ширина перехода 4 → 1,5 px: точки гаснут в линию, линия в тон; среднее по всем стадиям одно.
	float dots = grad_ok * smoothstep(1.5, 4.0, min(dot_px, slot_px * 0.5));
	float rows = grad_ok * smoothstep(1.5, 4.0, row_px);

	float row_id = floor(phase / max(row_step, 1e-4));
	float d_row = phase - (row_id + 0.5) * row_step;
	float peak = present * (2.0 * row_radius) / max(dot_step, 1e-4);
	float line_cov = min(peak, 1.0) * cov1d(d_row, row_radius, fw_phase);
	vec3 col_line = mix(void_rgb, point_rgb, line_cov);

	float slot = floor(along / max(dot_step, 1e-4));
	ivec2 cell = ivec2(int(slot), int(row_id));
	float j = (scan_hash(cell + ivec2(0, 17)) - 0.5) * 2.0 * row_jitter;
	float center = (slot + 0.5 + j) * dot_step;
	float show = step(scan_hash(cell), present) * step(1e-4, present);
	float dot_cov = show * cov1d(along - center, row_radius, fw_along) * cov1d(d_row, row_radius, fw_phase);
	vec3 col_dot = mix(void_rgb, point_rgb, dot_cov);
	if (scan_debug > 2.5) {
		return col_dot;
	}

	vec3 col = mix(col_mean, col_line, rows);
	return mix(col, col_dot, dots);
}
