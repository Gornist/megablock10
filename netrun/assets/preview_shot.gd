extends Node
## Снимает кадры камер preview.tscn в PNG: отдельный процесс Godot на дисплее devbox (редактор не нужен).
##   godot --path <копия netrun> res://assets/preview_shot.tscn [-- --out=/каталог/для/png/]
## Камеры и имена файлов — в SHOTS; кадр берётся из SubViewport фиксированного размера, поэтому от окна не зависит.

## камера -> [имя файла, размер кадра]
const SHOTS := {
	"CamOverview": ["preview", Vector2i(1500, 900)],
	"CamCreatures": ["preview_creatures", Vector2i(1500, 700)],
	"CamDeck": ["preview_deck", Vector2i(1100, 900)],
	"CamTokens": ["preview_tokens", Vector2i(1500, 560)],
	"CamTiers": ["preview_tiers", Vector2i(1500, 900)],
}


func _ready() -> void:
	var out := ProjectSettings.globalize_path("res://assets/previews/")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	var vp := SubViewport.new()
	vp.size = Vector2i(1500, 900)
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var scene := (load("res://assets/preview.tscn") as PackedScene).instantiate()
	vp.add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	scene.freeze()
	for cam_name in SHOTS:
		vp.size = SHOTS[cam_name][1]
		(scene.get_node(cam_name) as Camera3D).make_current()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var path: String = out.path_join(SHOTS[cam_name][0] + ".png")
		var err := vp.get_texture().get_image().save_png(path)
		print("снимок ", cam_name, " -> ", path, " (", error_string(err), ")")
	get_tree().quit()
