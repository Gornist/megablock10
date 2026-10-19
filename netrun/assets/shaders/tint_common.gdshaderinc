// Перекраска тиром — общая часть шейдеров окружения (solid_dark, skirt, shell_soft, points, streaks, beacon_halo; раньше копировалась в каждый, аудит 17.10 №5).
// Тир (BASE голубой, HARD синий, NIGHTMARE фиолетовый) задаёт AssetMaterials: tint — цвет тира, tint_amount — доля перекраски (1 — целиком в tint).
uniform vec4 tint : source_color = vec4(1.0);
uniform float tint_amount : hint_range(0.0, 1.0) = 0.0;

// Тир перекрашивает цвет ассета в tint, но белые акценты (проёмы, порог, узлы) остаются белыми: чем ближе цвет к белому, тем меньше перекраска.
vec3 recolor(vec3 c) {
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	return mix(tint.rgb * mx, c, mn / max(mx, 0.0001));
}
