class_name GlowSource
extends Node3D
## Видимый светящийся источник (вид V11, решение владельца 31.10, стайлгайд разд. 5–6): маленькое яркое ядро и мягкий ореол-квад,
## оба — билборды, смотрят на камеру. «Одна-две яркие вещи в кадре, остальное тихо»: ставится только у портала, хранилища и выхода.
## Источник не пишет глубину и никого не освещает (свет облака — CloudLightPlan, как раньше).
## Материал ореола: AssetMaterials.halo_material(kind), если Blender его даст; иначе временная заглушка ниже.

const KINDS := ["portal", "vault", "exit"]
const CORE_SIZE := 0.12   ## сторона квада ядра, м
## Высота над основанием и сторона ореола, м (по виду источника).
const HEIGHT := {"portal": 1.2, "vault": 1.0, "exit": 1.2}
const HALO_SIZE := {"portal": 1.6, "vault": 1.2, "exit": 2.0}
const RENDER_PRIORITY := 10   ## выше облаков: ореол рисуется поверх частиц
const HALO_ALPHA := 0.35      ## альфа цвета ореола в заглушке

## Временно, пока Blender не даст AssetMaterials.halo_material: билборд-шейдер (как client/load_probe.gd), аддитивный, глубину не пишет.
const STUB_SHADER := """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;
uniform vec4 tint : source_color = vec4(1.0);
uniform float power = 2.5;
varying vec2 uvq;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	uvq = UV * 2.0 - 1.0;
}
void fragment() {
	float r = clamp(length(uvq), 0.0, 1.0);
	ALBEDO = tint.rgb;
	ALPHA = tint.a * pow(1.0 - r, power);
}
"""

var kind := ""
var core: MeshInstance3D
var halo: MeshInstance3D
var halo_from_assets := false   ## ореол взят из AssetMaterials.halo_material (а не заглушка)

static var _shader: Shader


func setup(source_kind: String) -> GlowSource:
	assert(source_kind in KINDS, "GlowSource: неизвестный вид " + source_kind)
	kind = source_kind
	name = "Glow_" + kind
	position = Vector3(0.0, float(HEIGHT[kind]), 0.0)
	core = _quad("Core", CORE_SIZE, _stub_material(1.0, 0.6))
	var assets_mat := _assets_halo(kind)
	halo_from_assets = assets_mat != null
	halo = _quad("Halo", float(HALO_SIZE[kind]), assets_mat if assets_mat != null else _stub_material(HALO_ALPHA, 2.5))
	return self


func _quad(node_name: String, size: float, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.name = node_name
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	m.mesh = q
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	return m


## Материал ореола от Blender, если метод уже есть (ссылка на скрипт: у статического имени класса has_method недоступен, как в render_config.apply_assets).
static func _assets_halo(source_kind: String) -> Material:
	var script: GDScript = AssetMaterials
	if script.has_method("halo_material"):
		return script.call("halo_material", source_kind) as Material
	return null


static func _stub_material(alpha: float, power: float) -> ShaderMaterial:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = STUB_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("tint", AssetMaterials.layer("hud_ok", alpha))
	mat.set_shader_parameter("power", power)
	mat.render_priority = RENDER_PRIORITY
	return mat
