// Фон-купол: внутренняя сторона большой сферы вокруг головы, как лобби Pico (решение владельца 18.10: «дальний фон/горизонт — внутренностью большого шара»).
// Вместо дальней геометрии с частицами (на очках она мерцала и обрывалась видимой границей): почти-чёрная нейтральная пустота, лёгкая бирюзовая дымка у горизонта и
// НЕПОДВИЖНЫЕ пылинки из запечённой текстуры (референсы CDPR: дальнее не обрывается, а растворяется в чёрном; sub-пиксельных точек и хеша в шейдере нет — они сами мерцают).
// Купол в прозрачном проходе (после непрозрачного мира) с обычным тестом глубины и без записи: на дальности DOME_R от головы он виден только там, где ничего ближе нет (пол, кубы, стойки закрывают его). Слой деки (xr_layer_host) вырезается по глубине панели.
// В вершинном шейдере из вида берётся только поворот: купол всегда в центре головы, следить за позицией камеры клиенту не нужно. Камера клиента должна видеть дальше DOME_R (у XR-камеры far ≥ 100 м).
shader_type spatial;
render_mode unshaded, blend_premul_alpha, cull_front, depth_draw_never, fog_disabled, shadows_disabled;
// blend_premul_alpha при ALPHA = 0 — чисто аддитивный свет: альфа кадра не трогается. Клиент рисует вид с прозрачным фоном (transparent_bg) и слоем деки позади (xr_layer_host, layers = behind):
// непрозрачный купол закрыл бы слой деки (19.10 на очках «пропала дека»), а свет поверх прозрачного фона слой оставляет видимым.

#include "backdrop_sky.gdshaderinc"
uniform sampler2D sky_dust_tex : filter_linear, repeat_enable;   // равнопромежуточная развёртка пылинок (BackdropDome.dust_texture), R — яркость
uniform vec3 sky_dust_color : source_color = vec3(0.45, 0.85, 0.95);
uniform float sky_dust_gain : hint_range(0.0, 2.0) = 0.5;           // ручка `backdrop_dust`

const float DOME_R = 60.0;
varying vec3 v_dir;

void vertex() {
	v_dir = VERTEX;
	POSITION = PROJECTION_MATRIX * vec4(mat3(VIEW_MATRIX) * (MODEL_MATRIX * vec4(VERTEX, 0.0)).xyz * DOME_R, 1.0);   // направление × DOME_R в виде: поворот головы без сдвига
}

void fragment() {
	vec3 d = normalize(v_dir);
	vec2 uv = vec2(atan(d.x, -d.z) / 6.28318 + 0.5, acos(clamp(d.y, -1.0, 1.0)) / 3.14159);
	float dust = texture(sky_dust_tex, uv).r;
	ALBEDO = backdrop_sky(d) + sky_dust_color * dust * sky_dust_gain;
	ALPHA = 0.0;
}
