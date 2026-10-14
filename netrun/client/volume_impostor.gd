class_name VolumeImpostor
extends RefCounted
## Импостор дальних облаков (способ 3 из docs/netrun-refactor-plan.md, §4.1): далеко от камеры облако частиц заменяется одним билбордом —
## текстурой, один раз «запечённой» в SubViewport. Цена дальнего облака падает с тысяч квадов до одного. Ручка — `[render] volume_impostor_m`
## (порог, м; 0 — выкл. по умолчанию, пока не измерено). Здесь — чистая логика порога с гистерезисом и сборка запечённого билборда.

## Ширина полосы гистерезиса, м: переключение «близко → далеко» на threshold + HYSTERESIS, обратно — на threshold − HYSTERESIS
## (иначе облако на границе мигает между режимами).
const HYSTERESIS := 1.0
## Сторона запечённой текстуры, px.
const TEXTURE_SIZE := 256
## Запас кадра вокруг габарита облака при запекании (доля).
const FRAME_MARGIN := 1.1


## Следующее состояние «далеко» (true — рисуем билборд). threshold <= 0 — импостор выключен (всегда false).
static func next_far(currently_far: bool, distance: float, threshold: float) -> bool:
	if threshold <= 0.0:
		return false
	if currently_far:
		return distance > threshold - HYSTERESIS
	return distance > threshold + HYSTERESIS


## Билборд с запечённым видом облака спереди (вдоль −Z локальной системы) или null, если габарит пуст.
## multimesh — живое облако (копируется: у копии видимы все точки, а не префикс по ЛОД); bounds — габарит в локальной системе облака.
## SubViewport живёт в мире своего собственного (own_world_3d), рендерится один раз; Sprite3D стоит в центре габарита и смотрит на камеру.
static func bake(multimesh: MultiMesh, bounds: AABB) -> Node3D:
	if multimesh == null or bounds.size.length() <= 0.0:
		return null
	var root := Node3D.new()
	root.name = "Impostor"
	var vp := SubViewport.new()
	vp.size = Vector2i(TEXTURE_SIZE, TEXTURE_SIZE)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	root.add_child(vp)
	var full := multimesh.duplicate() as MultiMesh
	full.visible_instance_count = -1   # все точки: у живого облака по ЛОД виден только префикс (на расстоянии — самый редкий)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = full
	vp.add_child(mmi)
	var span := maxf(bounds.size.x, bounds.size.y) * FRAME_MARGIN
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = span
	cam.near = 0.05
	cam.far = bounds.size.z + 4.0
	vp.add_child(cam)
	var c := bounds.get_center()
	cam.position = Vector3(c.x, c.y, bounds.end.z + 2.0)   # смотрим вдоль −Z
	var sprite := Sprite3D.new()
	sprite.texture = vp.get_texture()
	sprite.pixel_size = span / float(TEXTURE_SIZE)
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = false
	sprite.transparent = true
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.position = c
	root.add_child(sprite)
	return root
