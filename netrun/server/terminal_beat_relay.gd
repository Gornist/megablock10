class_name TerminalBeatRelay
extends RefCounted
## Пересылка состояния очков (P6) из сервера мира в Мост: NetServer.beat_received -> terminal.beat.
## Частоту ограничивает NetServer (раз в период на терминал); здесь — перевод полей: link из RTT, остальное как есть.
## Заряд-зарядка, худший кадр и RTT в протокол Моста пока не входят (там battery, fps, link) — остаются в журнале сервера.

var bridge: BridgeApi
var sent := 0
var failed := 0


func _init(net: NetServer, bridge_api: BridgeApi) -> void:
	bridge = bridge_api
	net.beat_received.connect(_on_beat)


func _on_beat(beat: Dictionary) -> void:
	var rtt := int(beat.get("rtt", -1))
	@warning_ignore("redundant_await")  # у настоящего Моста ответ по сети
	var r: Dictionary = await bridge.terminal_beat(str(beat["terminal"]), int(beat.get("bat", -1)), int(beat.get("fps", -1)), BeatStats.link_from_rtt(rtt))
	if r.get("ok", false):
		sent += 1
	else:
		failed += 1
		print("[netrun-server] terminal.beat ", beat["terminal"], " не принят: ", BridgeApi.err_code(r))
