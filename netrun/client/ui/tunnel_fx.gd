class_name TunnelFx
extends Node3D
## Цифровой тоннель между узлами (W1): тёмная сфера вокруг головы, по ней бегут тусклые полосы — поток вокруг игрока.
## Комфорт (docs/netrun.md, «VR: сидя»): камера не двигается и не вращается, всё это — шейдер на самой сфере; вход и выход —
## плавное затемнение, без вспышек; контраст полос низкий. Пока сфера непрозрачна, сцена за ней меняется незаметно.
## Крепится к камере (rig.camera); fade — 0 (нет) … 1 (сплошной).

const FADE_IN_SEC := 0.5
const FADE_OUT_SEC := 0.7

const SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, blend_mix;
uniform float fade = 0.0;
uniform float flow = 3.0;
varying vec3 lp;
void vertex() { lp = VERTEX; }
void fragment() {
	float ring = 0.5 + 0.5 * sin(lp.z * 6.0 - TIME * flow);
	float spoke = 0.5 + 0.5 * sin(atan(lp.y, lp.x) * 10.0);
	float stripe = smoothstep(0.55, 1.0, ring) * (0.35 + 0.65 * spoke);
	vec3 base = vec3(0.01, 0.02, 0.04);
	vec3 glow = vec3(0.05, 0.45, 0.6);
	ALBEDO = mix(base, glow, stripe * 0.35);
	ALPHA = fade * 0.97;
}
"""

var fade := 0.0:
	set(v):
		fade = clampf(v, 0.0, 1.0)
		if _mat != null:
			_mat.set_shader_parameter("fade", fade)
		visible = fade > 0.0
var _mat: ShaderMaterial
var _tween: Tween


func _init() -> void:
	name = "TunnelFx"
	visible = false
	var sh := Shader.new()
	sh.code = SHADER_CODE
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	var mesh := SphereMesh.new()
	mesh.radius = 1.5
	mesh.height = 3.0
	mesh.radial_segments = 24
	mesh.rings = 12
	mesh.material = _mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Тоннель начался: плавно затемнить.
func begin() -> void:
	_fade_to(1.0, FADE_IN_SEC)


## Тоннель кончился (игрок уже в новом узле): плавно открыть.
func finish() -> void:
	_fade_to(0.0, FADE_OUT_SEC)


func is_active() -> bool:
	return fade > 0.0


func _fade_to(target: float, sec: float) -> void:
	if _tween != null:
		_tween.kill()
	if not is_inside_tree():
		fade = target
		return
	_tween = create_tween()
	_tween.tween_property(self, "fade", target, sec * absf(target - fade) if absf(target - fade) > 0.0 else 0.0)
