// ЭКСПЕРИМЕНТ «стеклянный пол» (меш `*_glass` в env/floor_glass_<N>, имя подменяет шейдер на этот): верх плиты-пола как матовое светящееся стекло.
// Чёрное в аддитиве невидимо, поэтому верх — тёмно-бирюзовый слой с очень низкой альфой: сквозь него угадываются дальние пласты ниже и отражение, а сама плита слегка
// светится изнутри мягкой дымкой. Один квад на всю плиту; UV 0…1 по плите дают расстояние до кромки: у кромки дымка плотнее, к центру темнее (`edge_len`, `center_k`),
// по плите плавная пятнистость (шум по мировой позиции, медленный дрейф), у самой кромки тонкий контур верха (`rim_*`) — масштаб и граница читаются.
// Аддитивный, без освещения, без записи глубины и без чтения буфера глубины (без depth-fade; замена — fade_start/fade_end). Двусторонний. Цвет — из цвета вершин.
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, fog_disabled;

uniform float glow : hint_range(0.0, 4.0) = 1.0;
uniform float glass_alpha : hint_range(0.0, 0.5) = 0.17;   // непрозрачность у кромки; к центру — glass_alpha·center_k (≈ 0,11…0,17 в итоге; было 0,095 и 0,45: пол под ногами читался слабо)
uniform float center_k : hint_range(0.0, 1.0) = 0.65;     // яркость центра плиты относительно кромки
uniform float edge_len : hint_range(0.2, 6.0) = 1.8;       // длина затухания от кромки к центру, м
uniform float patch_amount : hint_range(0.0, 1.0) = 0.7;   // пятнистость (0 — ровная плёнка)
uniform float patch_scale : hint_range(0.1, 4.0) = 0.55;   // пятен на метр
uniform float patch_drift : hint_range(0.0, 0.2) = 0.02;   // медленное плавание пятен, 1/с (комфорт в VR)
uniform float rim_width : hint_range(0.005, 0.2) = 0.03;   // ширина контура верха, м
uniform float rim_alpha : hint_range(0.0, 1.0) = 0.5;      // яркость контура верха
uniform float plate_size = 8.0;                            // сторона плиты, м (AssetMaterials берёт из AABB меша)
uniform vec4 tint : source_color = vec4(1.0);
uniform float tint_amount : hint_range(0.0, 1.0) = 0.0;
uniform float fade_start = 60.0;
uniform float fade_end = 90.0;
uniform float intensity = 1.0; // общий множитель яркости (отражение в полу = 0.2)

varying vec3 v_wp;
varying float v_dist;

vec3 recolor(vec3 c) {
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	return mix(tint.rgb * mx, c, mn / max(mx, 0.0001));
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
// гладкий двумерный шум (значения в узлах решётки, интерполяция сглаженная)
float vnoise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	v_wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_dist = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}

void fragment() {
	vec2 e = min(UV, vec2(1.0) - UV) * plate_size; // расстояние до ближайшей кромки по каждой оси, м
	float d = min(e.x, e.y);
	float edge_k = mix(center_k, 1.0, exp(-d / edge_len));
	vec2 q = v_wp.xz * patch_scale + vec2(TIME * patch_drift, -TIME * patch_drift * 0.7);
	float n = 0.6 * vnoise2(q) + 0.4 * vnoise2(q * 2.7 + 11.3);
	float patch_k = mix(1.0, n * 1.7, patch_amount);
	float rim = (1.0 - smoothstep(0.0, rim_width, d)) * rim_alpha;
	float fade = 1.0 - smoothstep(fade_start, fade_end, v_dist);
	vec3 col = mix(COLOR.rgb, recolor(COLOR.rgb), tint_amount);
	ALBEDO = col * glow;
	ALPHA = clamp((glass_alpha * edge_k * patch_k + rim) * fade * intensity, 0.0, 1.0);
}
