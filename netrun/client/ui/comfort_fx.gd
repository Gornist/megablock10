class_name ComfortFx
extends MeshInstance3D
## Затемнение перед камерой для комфорта в VR: одно общее на моргание телепорта (весь экран, 0 -> 1 -> 0 за ~0,2 с) и на виньетку при
## повороте (темнеют края поля зрения, чем быстрее поворот, тем сильнее). Один квад с шейдером, без постобработки — для
## Mobile-рендерера на Pico 4 это один дешёвый вызов отрисовки; при нулевых значениях квад скрыт и ничего не стоит.
## Крепится к камере (rig.camera). Угол считается от оси взгляда по положению пикселя в пространстве камеры, поэтому от размера
## квада и от формы поля зрения глаза (асимметричные матрицы очков) не зависит. Камеру не двигает и не вращает.

## Угол, на котором виньетка при любой силе гарантированно чёрная (рад, ~54°): половина поля зрения Pico 4 с запасом.
const HALF_FOV_RAD := 0.95
## Ширина мягкого перехода от прозрачного к чёрному (рад).
const EDGE_SOFT_RAD := 0.35

const SHADER_CODE := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled;
uniform float blink = 0.0;
uniform float vignette = 0.0;
uniform float half_fov = 0.95;
uniform float soft = 0.35;
void fragment() {
	float ang = acos(clamp(dot(normalize(VERTEX), vec3(0.0, 0.0, -1.0)), -1.0, 1.0));
	float clear_to = half_fov * (1.0 - vignette);
	float edge = vignette > 0.0 ? smoothstep(clear_to, clear_to + soft, ang) : 0.0;
	ALBEDO = vec3(0.0);
	ALPHA = max(edge, blink);
}
"""

var blink := 0.0 : set = set_blink
var vignette := 0.0 : set = set_vignette
var _mat: ShaderMaterial


func _init() -> void:
	name = "ComfortFx"
	visible = false
	var sh := Shader.new()
	sh.code = SHADER_CODE
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.render_priority = 110
	_mat.set_shader_parameter("half_fov", HALF_FOV_RAD)
	_mat.set_shader_parameter("soft", EDGE_SOFT_RAD)
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	quad.material = _mat
	mesh = quad
	position = Vector3(0.0, 0.0, -0.25)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16.0   # квад перед камерой не должен выпадать из кадра по границам


## Полное затемнение, 0…1 (моргание телепорта).
func set_blink(v: float) -> void:
	blink = clampf(v, 0.0, 1.0)
	_mat.set_shader_parameter("blink", blink)
	_refresh()


## Затемнение краёв, 0…TURN_VIGNETTE_LIMIT (доля поля зрения по радиусу, закрытая у краёв).
func set_vignette(v: float) -> void:
	vignette = clampf(v, 0.0, RigMath.TURN_VIGNETTE_LIMIT)
	_mat.set_shader_parameter("vignette", vignette)
	_refresh()


func is_active() -> bool:
	return blink > 0.0 or vignette > 0.0


func _refresh() -> void:
	visible = is_active()
