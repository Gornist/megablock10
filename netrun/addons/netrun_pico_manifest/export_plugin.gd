@tool
extends EditorExportPlugin
## Добавляет в манифест Android-экспорта записи Pico (PicoManifest). Работает только для платформы Android со сборкой через gradle.


const Manifest := preload("res://addons/netrun_pico_manifest/pico_manifest.gd")   # без зависимости от кэша class_name при экспорте


func _get_name() -> String:
	return "NetrunPicoManifest"


func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformAndroid


func _get_android_manifest_application_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
	return Manifest.application_contents()
