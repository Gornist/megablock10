class_name BuildInfo
extends RefCounted
## Номер сборки для тестеров: в репозитории «dev», скрипт tools/export_flat_win.sh подставляет в копии проекта `<дата>-<короткий sha>`
## (например 1017-ab12cd3). Тестер называет его в отчёте — по нему находим коммит. Строка подставляется скриптом: формат менять только вместе с ним.

const BUILD := "dev"


## Допустимый номер: непусто, только строчные латинские буквы, цифры и дефис (имя файла build/netrun-solo.txt и метка в отчётах).
static func is_valid(s: String) -> bool:
	return RegEx.create_from_string("^[a-z0-9\\-]+$").search(s) != null
