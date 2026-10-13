class_name PicoManifest
extends RefCounted
## Что клиент объявляет в AndroidManifest для Pico (без плагина godot_openxr_vendors): чистые строки, чтобы их проверял обычный тест.
## Без этих записей система на очках со спящими контроллерами и включённым отслеживанием рук не запускает игру и показывает
## «Требуется контроллер — приложение не поддерживает отслеживание рук» (com.picovr.systemext/.HandDialogActivity; «vr app is not support hand mode»).
## handtracking=1 — как в godot_openxr_vendors (issue #162, PR #216): убирает это окно. pvr.app.type=vr — тип приложения по документации Pico OpenXR (глава 4).

const META_DATA := {
	"pvr.app.type": "vr",
	"handtracking": "1",
}


## Содержимое <application>: по одному <meta-data> на запись.
static func application_contents() -> String:
	var out := ""
	for key: String in META_DATA:
		out += "\t\t<meta-data android:name=\"%s\" android:value=\"%s\" />\n" % [key, META_DATA[key]]
	return out
