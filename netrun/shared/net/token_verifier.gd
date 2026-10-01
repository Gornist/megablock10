class_name TokenVerifier
extends RefCounted
## Интерфейс проверки токена терминала: возвращает id сессии игрока или "" (отказ).
## Настоящая реализация — запрос к Мосту (server/bridge/bridge_api.gd: BridgeClient, FakeBridge); DictTokenVerifier — словарь из аргументов.

func verify(_token: String) -> String:
	return ""


## Для верификаторов, которым нужна сеть (Мост): вызывается с await. По умолчанию — обычная verify.
func verify_async(token: String) -> String:
	return verify(token)
