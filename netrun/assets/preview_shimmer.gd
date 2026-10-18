extends Node3D
## Рябь облака при микродвижении головы (очки 18.10: «вдали рябит больше», «лесенка жёстче»): Фойе глазами игрока, кадр как у приложения на Pico 4 (1504×1504, msaa как в клиенте),
## камера сдвигается между кадрами на доли пикселя (тремор головы); меряется средняя разница яркости соседних кадров по трём полосам кадра: верх — потолок и дальние пласты,
## середина — горизонт и колонны, низ — пол вблизи. Неподвижная ровная картинка даёт ≈0, зерно, у которого покрытие перескакивает между пикселями, — много.
## Запуск: netrun/tools/dev.sh shot res://assets/preview_shimmer.tscn [--lights] [--msaa=0|2|4] [--tune=dust_fill=0,...] [--pose=entry|wedge|north]
## В журнал: `shimmer <поза> msaa=…: верх=… середина=… низ=… всё=…`; кадры <поза>_a/_b — первый и шестой.
## Метрика сравнительная (одна сцена, разные ручки), не абсолютная: в уровень входит и честный сдвиг резких краёв. Дыхание облака (cloud_breath) даёт отдельную временную
## составляющую (≈1,2 из 3,5 на умолчаниях) — для чистого замера ряби от сдвига ставьте --tune=cloud_breath=0.

## Кадр на глаз, как рисует приложение на Pico 4 (xr-diag target_size=1504×1504), а не 2160×2160 панели: пиксель крупнее, ячейки облака относительно него мельче.
const EYE := Vector2i(1504, 1504)
const DX := 0.0004   # м: сдвиг позы между кадрами
const DYAW := 0.011  # градусы (≈ 0,2 px)

var _out := "/tmp/shimmer_shots"
var _pose := "entry"
var _msaa := -1
var _lights := false   # --lights: невидимые источники света у хранилищ, порталов и входа (AssetMaterials.set_cloud_lights)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--pose="):
			_pose = a.substr(7)
		elif a == "--lights":
			_lights = true
		elif a.begins_with("--msaa="):
			_msaa = int(a.substr(7))
		elif a.begins_with("--tune="):
			var d := {}
			for kv in a.trim_prefix("--tune=").split(","):
				var p := kv.split("=")
				if p.size() == 2:
					d[p[0]] = p[1]
			AssetMaterials.tune(d)
	DirAccess.make_dir_recursive_absolute(_out)
	var scene: Node3D = preload("res://client/rig_test_scene.gd").new()
	add_child(scene)
	await get_tree().process_frame
	var foyer := LayoutData.cached("foyer")
	scene.apply_node({"kind": "node", "node": "foyer", "title": "Фойе", "tier": "BASE", "r": NodeLayout.PORTAL_RADIUS, "shards": [], "portals": [], "layout": foyer.name})
	scene.apply_state({"k": Time.get_ticks_msec() / 1000.0, "trace": 0.0, "level": 0, "cd": [], "ice": [], "bk": [], "sn": [], "tk": {"n": 4, "at": 0.0, "win": 5.0, "inh": 0, "mv": 0}})
	if _lights:
		var ls: Array = []
		for v: Dictionary in foyer.vaults:
			ls.append({"p": v["slot"], "r": 3.5})
		for q: Vector3 in foyer.portals:
			ls.append({"p": q + Vector3(0.0, 0.5, 0.0), "r": 3.5})
		var eye: Vector3 = EyePresets.get_preset(_pose, null)["pos"]
		ls.append({"p": Vector3(eye.x, 0.0, eye.z), "r": 4.0})
		AssetMaterials.set_cloud_lights(get_tree(), ls)
	var render := RenderConfig.new()
	if _msaa >= 0:
		render.msaa = _msaa
	var vp := SubViewport.new()
	vp.size = EYE
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	render.apply_msaa(vp)
	add_child(vp)
	var cam := Camera3D.new()
	vp.add_child(cam)
	var p := EyePresets.get_preset(_pose, null)
	cam.fov = p["fov"]
	cam.look_at_from_position(p["pos"], p["look"], p["up"])
	cam.current = true
	var base := cam.global_transform
	var sums := [0.0, 0.0, 0.0, 0.0]
	var prev: Image = null
	var n := 0
	for k in 6:
		var t := base
		t.origin += base.basis.x * DX * float(k)
		t.basis = Basis(Vector3.UP, deg_to_rad(DYAW) * float(k)) * base.basis
		cam.global_transform = t
		for i in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_L8)
		if k == 0 or k == 5:
			img.save_png("%s/%s_%s.png" % [_out, _pose, "a" if k == 0 else "b"])
		if prev != null:
			var d := _band_diff(prev, img)
			for j in 4:
				sums[j] += d[j]
			n += 1
		prev = img
	for j in 4:
		sums[j] /= float(maxi(n, 1))
	print("shimmer %s msaa=%d: верх=%.3f середина=%.3f низ=%.3f всё=%.3f (средняя |разница соседних кадров| при сдвиге ≈0,2 px, 0…255; меньше — стабильнее)" % [_pose, vp.msaa_3d, sums[0], sums[1], sums[2], sums[3]])
	get_tree().quit()


## Средняя |разница| двух кадров L8 по полосам (верх, середина, низ) и по всему кадру.
func _band_diff(a: Image, b: Image) -> Array:
	var da := a.get_data()
	var db := b.get_data()
	var w := a.get_width()
	var h := a.get_height()
	var acc := [0.0, 0.0, 0.0]
	var cnt := [0, 0, 0]
	for y in range(0, h, 2):
		var band := mini(int(3.0 * y / h), 2)
		var row := y * w
		for x in range(0, w, 2):
			acc[band] += absi(int(da[row + x]) - int(db[row + x]))
			cnt[band] += 1
	var out := []
	var tot := 0.0
	var tn := 0
	for j in 3:
		out.append(acc[j] / maxf(cnt[j], 1))
		tot += acc[j]
		tn += cnt[j]
	out.append(tot / maxf(tn, 1))
	return out
