// Дыхание и отклик на приближение: общая часть облаков — объёмного (Б, particles_body.gdshaderinc) и поверхностного (А, cloud_dark.gdshaderinc).
// Состояния нет, времени шейдер не ведёт: всё приходит uniform'ами, которые клиент каждый кадр ставит через AssetMaterials.set_cloud_breath / set_cloud_touch.
// Умолчания — выкл. (breath_depth = 0, радиусы источников 0): без вызова клиента вид прежний, руки и тело не меняются.

// Дыхание: всё облако вдыхает единой волной, вдох — на тике хода. Фазу такта (0 — тик, 1 — следующий тик) задаёт клиент.
// Волна чуть бежит по миру (breath_spread): соседние объекты вдыхают с лёгким сдвигом, а не хлопают разом.
uniform float breath_depth : hint_range(0.0, 1.0) = 0.0;
uniform float breath_phase : hint_range(0.0, 1.0) = 0.0;
uniform float breath_spread : hint_range(0.0, 0.5) = 0.08;    // сдвиг фазы волны, долей такта на метр вдоль (x, y, z) ≈ (1, 0.5, 0.7)

// Отклик: до четырёх источников (рука, аватар), xyz — мир, w — радиус влияния, м (0 — источник выключен). Рядом с источником — ярче, крупнее, теплее, чуть расходятся.
uniform vec4 touch_a = vec4(0.0);
uniform vec4 touch_b = vec4(0.0);
uniform vec4 touch_c = vec4(0.0);
uniform vec4 touch_d = vec4(0.0);
uniform float touch_gain : hint_range(0.0, 4.0) = 1.2;        // прибавка яркости у самого источника
uniform float touch_grow : hint_range(0.0, 3.0) = 0.8;        // прибавка размера частицы (А: плотности частиц) у самого источника
uniform float touch_push : hint_range(0.0, 0.1) = 0.025;      // на сколько частица (Б) расходится от источника, м
uniform vec3 touch_color = vec3(0.85, 0.98, 1.0);             // цвет, к которому частицы уходят у источника (по умолчанию ice_white)

// Яркость от дыхания: 1 — как без дыхания; пик на тике, спад к концу такта; вдох короткий и резкий (квадрат косинуса), выдох долгий.
float breath_lift(vec3 w) {
	if (breath_depth <= 0.0) {
		return 1.0;
	}
	float ph = breath_phase - breath_spread * dot(w, vec3(1.0, 0.5, 0.7));
	float b = 0.5 + 0.5 * cos(6.28318 * ph);
	b *= b;
	return mix(1.0 - 0.45 * breath_depth, 1.0 + 0.35 * breath_depth, b);
}

// Близость к одному источнику 0…1 (1 — в нём, 0 — на радиусе и дальше); push копит направление «от источника».
float touch_near(vec4 t, vec3 p, inout vec3 push) {
	if (t.w <= 0.0) {
		return 0.0;
	}
	vec3 d = p - t.xyz;
	float k = 1.0 - smoothstep(0.0, t.w, length(d));
	push += normalize(d + vec3(0.0, 0.0001, 0.0)) * k;
	return k;
}

// Близость к ближайшему из источников 0…1; push — суммарный сдвиг «от источников».
float touch_k(vec3 p, inout vec3 push) {
	if (touch_a.w + touch_b.w + touch_c.w + touch_d.w <= 0.0) {
		return 0.0;
	}
	float k = touch_near(touch_a, p, push);
	k = max(k, touch_near(touch_b, p, push));
	k = max(k, touch_near(touch_c, p, push));
	return max(k, touch_near(touch_d, p, push));
}
