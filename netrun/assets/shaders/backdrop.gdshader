// Фон-купол: внутренняя сторона большой сферы вокруг головы, как лобби Pico (решение владельца 18.10: «дальний фон/горизонт — внутренностью большого шара»).
// Вместо дальней геометрии с частицами (на очках она мерцала и обрывалась видимой границей): почти-чёрная нейтральная пустота, лёгкая бирюзовая дымка у горизонта и
// НЕПОДВИЖНЫЕ пылинки из запечённой текстуры (референсы CDPR: дальнее не обрывается, а растворяется в чёрном; sub-пиксельных точек и хеша в шейдере нет — они сами мерцают).
// Купол рисуется первым (render_priority −128), не читает и не пишет глубину: всё остальное рисуется поверх него; слой деки (xr_layer_host) вырезается по глубине панели поверх.
// В вершинном шейдере из вида берётся только поворот: купол всегда в центре головы, следить за позицией камеры клиенту не нужно.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, depth_test_disabled, fog_disabled, shadows_disabled;

uniform vec3 void_color : source_color = vec3(0.0, 0.0, 0.0);      // пустота: AssetMaterials.alarm_background(level), её задаёт BackdropDome
uniform vec3 haze_color : source_color = vec3(0.03, 0.12, 0.15);     // дымка у горизонта: тусклая бирюза, не светлее дальних плит
uniform float haze_height : hint_range(0.05, 1.0) = 0.28;           // толщина дымки по sin высоты (0 — линия горизонта)
uniform float haze_below : hint_range(0.0, 2.0) = 1.0;               // ниже горизонта (пол уходит в даль) дымка гуще: у пола — бирюзовая мгла
uniform sampler2D dust_tex : filter_linear, repeat_enable;           // равнопромежуточная развёртка: R — яркость пылинки (BackdropDome.dust_texture)
uniform vec3 dust_color : source_color = vec3(0.45, 0.85, 0.95);
uniform float dust_gain : hint_range(0.0, 2.0) = 0.5;

varying vec3 v_dir;

void vertex() {
	v_dir = VERTEX;
	POSITION = PROJECTION_MATRIX * vec4(mat3(VIEW_MATRIX) * (MODEL_MATRIX * vec4(VERTEX, 0.0)).xyz, 1.0);   // единичное направление в виде: поворот головы без сдвига
}

void fragment() {
	vec3 d = normalize(v_dir);
	float y = d.y;
	float haze = exp(-pow(abs(y) / haze_height, 2.0)) * (y < 0.0 ? haze_below : 0.6);
	vec2 uv = vec2(atan(d.x, -d.z) / 6.28318 + 0.5, acos(clamp(y, -1.0, 1.0)) / 3.14159);
	float dust = texture(dust_tex, uv).r;
	ALBEDO = void_color + haze_color * haze + dust_color * dust * dust_gain;
}
