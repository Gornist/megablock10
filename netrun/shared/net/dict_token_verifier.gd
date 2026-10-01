class_name DictTokenVerifier
extends TokenVerifier
## Заглушка вместо Моста: словарь токен -> сессия из настроек.

var _tokens: Dictionary

func _init(tokens: Dictionary = {}) -> void:
	_tokens = tokens


func verify(token: String) -> String:
	return String(_tokens.get(token, ""))
