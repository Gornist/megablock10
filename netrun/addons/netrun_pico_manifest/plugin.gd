@tool
extends EditorPlugin
## Подключает экспорт-плагин манифеста Pico (export_plugin.gd) на время жизни редактора/экспорта.

const ExportPlugin := preload("res://addons/netrun_pico_manifest/export_plugin.gd")

var _export_plugin: EditorExportPlugin


func _enter_tree() -> void:
	_export_plugin = ExportPlugin.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	if _export_plugin != null:
		remove_export_plugin(_export_plugin)
		_export_plugin = null
