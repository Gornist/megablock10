class_name TokenVerifier
extends RefCounted
## Интерфейс проверки токена терминала: возвращает id сессии игрока или "" (отказ).
## Настоящая реализация — запрос к Мосту (F1/M5); пока — DictTokenVerifier.

func verify(_token: String) -> String:
	return ""
