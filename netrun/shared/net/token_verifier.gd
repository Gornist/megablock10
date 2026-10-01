class_name TokenVerifier
extends RefCounted
## Интерфейс проверки токена терминала: возвращает id сессии игрока или "" (отказ).
## Настоящая реализация — запрос к Мосту (server/bridge/bridge_api.gd: BridgeClient, FakeBridge); DictTokenVerifier — словарь из аргументов.

func verify(_token: String) -> String:
	return ""


## Для верификаторов, которым нужна сеть (Мост): вызывается с await. По умолчанию — обычная verify.
func verify_async(token: String) -> String:
	return verify(token)


## Терминал по токену: {"terminal": id, "session": id или ""}. Пустой terminal — токен не принят или терминалов нет
## (словарная заглушка). Терминал без сессии (очки ждут игрока) — «idle»: на связи, но без аватара (P6).
func verify_terminal_async(token: String) -> Dictionary:
	return {"terminal": "", "session": await verify_async(token)}
