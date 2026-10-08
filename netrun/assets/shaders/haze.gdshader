// Сплошная дымка у горизонта (меш `horizon_haze` в env/horizon_band, имя `*_haze` подменяет шейдер на этот): замкнутая цилиндрическая лента вокруг узла
// в один слой. Яркая бирюзовая полоса на уровне глаз, плавно гаснущая вверх и вниз; ближние плиты режут её чёрными силуэтами (глубину не пишем и не читаем).
// Вертикальный профиль — альфа вершин (0 внизу, 1 на уровне глаз, 0 вверху), здесь сглаживается (smoothstep) и сжимается/растягивается `shape`.
// Азимутальная неровность — низкочастотный шум по углу вокруг центра узла (чтобы дымка не была ровным кольцом) и тонкие вертикальные «штрихи» внутри неё (гладкий
// одномерный шум по углу, без жёстких границ ячеек). Движение очень медленное и слабое (комфорт в VR). Без освещения, постобработки, depth-fade (замена — fade_start/fade_end).
// Аддитивный: один слой с низкой альфой (overdraw на Pico 4 не мерили). Цвет — из цвета вершин; перекраска тира как у остальных (tint).
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, fog_disabled;

uniform float glow : hint_range(0.0, 4.0) = 1.0;
uniform float haze_alpha : hint_range(0.0, 1.0) = 0.55;      // итоговая непрозрачность на уровне глаз в самом ярком месте
uniform float shape : hint_range(0.3, 4.0) = 1.4;           // профиль по высоте: больше — уже и резче у линии горизонта, меньше — шире
uniform float noise_amount : hint_range(0.0, 1.0) = 0.45;   // неровность яркости по азимуту (0 — ровное кольцо)
uniform float noise_speed : hint_range(0.0, 0.2) = 0.02;    // дрейф неровности, рад/с
uniform float stripe_amount : hint_range(0.0, 1.0) = 0.3;   // тонкие вертикальные штрихи внутри дымки
uniform float stripe_count : hint_range(20.0, 1200.0) = 420.0; // штрихов по кругу
uniform vec4 tint : source_color = vec4(1.0);
uniform float tint_amount : hint_range(0.0, 1.0) = 0.0;
uniform float fade_start = 150.0;
uniform float fade_end = 260.0;
uniform float intensity = 1.0; // общий множитель яркости
uniform float mist_scale : hint_range(0.0, 1.0) = 1.0;   // множитель итоговой альфы дымки (ручка mist_alpha; 0 — меш скрывается совсем)
uniform float anim : hint_range(0.0, 1.0) = 1.0;  // 0 — дымка статична (дрейф неровности и штрихов остановлен): очки П5, «лава-лампа» на горизонте и краях комнаты (ручка drift_static)

varying vec3 v_rel;
varying float v_dist;

vec3 recolor(vec3 c) {
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	return mix(tint.rgb * mx, c, mn / max(mx, 0.0001));
}

float hash1(float x) {
	return fract(sin(x * 127.1 + 31.7) * 43758.5453);
}
// гладкий одномерный шум, замкнутый по кругу (период — целое число ячеек)
float vnoise(float x, float period) {
	float i = floor(x);
	float f = x - i;
	float a = hash1(mod(i, period));
	float b = hash1(mod(i + 1.0, period));
	return mix(a, b, f * f * (3.0 - 2.0 * f));
}

void vertex() {
	v_rel = VERTEX; // вокруг центра узла (Origin ленты), локальные координаты: лента не зависит от положения узла
	v_dist = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}

void fragment() {
	float az = atan(v_rel.z, v_rel.x); // −π…π
	float u = az / 6.2831853 + 0.5;    // 0…1 по кругу
	float prof = pow(smoothstep(0.0, 1.0, clamp(COLOR.a, 0.0, 1.0)), shape);
	float drift = TIME * anim * noise_speed;
	float n = 0.5 + 0.28 * sin(az * 3.0 + drift * 6.0) + 0.22 * sin(az * 7.0 - drift * 9.0 + 1.3);
	float k_noise = mix(1.0, n * 1.6, noise_amount);
	float st = vnoise(u * stripe_count + TIME * anim * 0.05, stripe_count);
	float k_stripe = mix(1.0, st * 1.5, stripe_amount);
	float fade = 1.0 - smoothstep(fade_start, fade_end, v_dist);
	vec3 col = mix(COLOR.rgb, recolor(COLOR.rgb), tint_amount);
	ALBEDO = col * glow;
	ALPHA = clamp(prof * k_noise * k_stripe * haze_alpha * fade * intensity * mist_scale, 0.0, 1.0);
}
