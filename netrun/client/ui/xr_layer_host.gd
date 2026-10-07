class_name XrLayerHost
extends Node3D
## Панель слоем композитора OpenXR (OpenXRCompositionLayerQuad) вместо 3D-квада в буфере глаза: композитор рисует тот же SubViewport в
## разрешении дисплея и без дисторсии 3D-растеризации, поэтому текст и прямые линии чёткие (как лобби Pico).
##
## Включается, только если одновременно: поднят OpenXR, в netrun.cfg `[render] layers = "on"` (XrLayerHost.layers_requested ставит XrRig),
## класс слоя есть в этой сборке и рантайм поддерживает слои (`is_natively_supported()`). Иначе хост ничего не делает, 3D-квад панели остаётся.
## Когда слой активен, квад панели скрывается (`face.visible = false`); поза поверхности для указателя (`face.global_transform`) от видимости не
## зависит, поэтому DeckPointer работает как раньше.
##
## Решение принимается один раз, в первом _process: к этому времени XrRig.start_xr уже отработал (панели строятся раньше, чем стартует XR).

const LAYER_CLASS := "OpenXRCompositionLayerQuad"

## Просили ли слои в конфиге (XrRig.start_xr выставляет из RenderConfig.layers; по умолчанию выкл.).
static var layers_requested := false

var _viewport: SubViewport
var _size_m := Vector2.ONE
var _face: Node3D
var _visible_source: Node3D
var _layer: Node3D
var _decided := false


## Чистый выбор: слой — только при поднятом XR, включённом конфиге и поддержке рантаймом.
static func should_use_layer(xr: bool, cfg_on: bool, supported: bool) -> bool:
	return xr and cfg_on and supported


## OpenXR поднят (интерфейс найден и инициализирован).
static func xr_running() -> bool:
	var iface := XRServer.find_interface("OpenXR")
	return iface != null and iface.is_initialized()


## viewport — SubViewport панели; size_m — размер квада в метрах до масштаба (масштаб берётся из face); face — узел-поверхность панели
## (его global_transform слой повторяет); visible_source — чья видимость в дереве включает слой (по умолчанию родитель face: сам face
## при активном слое скрыт).
func setup(viewport: SubViewport, size_m: Vector2, face: Node3D, visible_source: Node3D = null) -> void:
	_viewport = viewport
	_size_m = size_m
	_face = face
	_visible_source = visible_source if visible_source != null else face.get_parent_node_3d()


## Слой создан и показывает панель (3D-квад скрыт).
func is_active() -> bool:
	return _layer != null


func _process(_delta: float) -> void:
	if not _decided:
		_decided = true
		_try_activate()
	if _layer != null:
		_sync_layer()


func _try_activate() -> void:
	if _viewport == null or _face == null:
		return
	var xr := xr_running()
	if not xr or not layers_requested or not ClassDB.class_exists(LAYER_CLASS):
		return
	var layer := ClassDB.instantiate(LAYER_CLASS) as Node3D
	if layer == null:
		return
	var supported: bool = layer.call("is_natively_supported")
	if not should_use_layer(xr, layers_requested, supported):
		layer.free()
		return
	layer.name = "XrLayer"
	layer.set("layer_viewport", _viewport)
	layer.set("alpha_blend", true)
	layer.set("quad_size", _size_m)
	_layer = layer
	add_child(_layer)
	_sync_layer()
	_face.visible = false


## Слой повторяет позу поверхности: ориентация без масштаба, а масштаб деки (на запястье 0,75) — в размер квада.
func _sync_layer() -> void:
	var t := _face.global_transform
	var sc := t.basis.get_scale()
	_layer.global_transform = Transform3D(t.basis.orthonormalized(), t.origin)
	_layer.set("quad_size", _size_m * Vector2(sc.x, sc.y))
	_layer.visible = _visible_source == null or _visible_source.is_visible_in_tree()
