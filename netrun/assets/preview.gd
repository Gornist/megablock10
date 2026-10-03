extends Node3D
## Сцена приёмки 3D-ассетов «Сети» (все группы набора: env, props, ice, avatar, deck). Собирает её
## src/make_preview_scene.py — править сцену руками не нужно, правьте скрипт. Здесь только запуск клипов существ:
## у узла-существа в группе creature метаданные anim (имя клипа) и anim_t (с какой секунды показывать).


func _ready() -> void:
	for n in get_tree().get_nodes_in_group("creature"):
		var ap := n.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap != null and n.has_meta("anim"):
			ap.play(String(n.get_meta("anim")))
			ap.seek(float(n.get_meta("anim_t", 0.0)), true)


## Остановить клипы на показанном кадре (для снимков).
func freeze() -> void:
	for n in get_tree().get_nodes_in_group("creature"):
		var ap := n.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap != null:
			ap.pause()
