extends SceneTree
## Стенд замера G2 (docs/netrun-bench.md): N узлов в одном мире + M ботов в одном процессе с сервером.
## Запуск (--quit-after — ДО «--», иначе процесс не выходит; кадров берём с запасом, выход — по --seconds):
##   godot --headless --path netrun --quit-after 6000 -s res://tools/bench_world.gd -- --nodes=12 --bots=10 --seconds=60
## Аргументы: --nodes=12, --bots=10, --seconds=60, --occupied=<узлов с ботами; по умолчанию 2/3 узлов>, --port=18400.
## Каждый узел — свой GrayNode (node_01…), ICE в нём 1 или 2 (чётные — 2, нечётные — 1). Боты (LOITER) раскиданы по первым
## <occupied> узлам, остальные узлы пустые: их ICE спит. Мост не используется (токены из словаря, ценностей нет).

const REPORT_SEC := 5.0

var _nodes: Array[GrayNode] = []
var _bots: Array[BotClient] = []
var _server: NetServer
var _n_nodes := 12
var _n_bots := 10
var _seconds := 60.0
var _occupied := 0
var _port := 18400

var _t := 0.0
var _next_report := REPORT_SEC
var _frames := 0
var _frame_ms_sum := 0.0
var _w_frames := 0
var _w_frame_ms := 0.0
var _w_totals: Array[int] = []
var _w_counts: Array[int] = []
var _w_bytes := 0
var _w_t := 0.0
var _all_frames := 0
var _all_frame_ms := 0.0
var _step_max_all := 0
var _sent_all_bytes_start := 0
var _done := false
var _built := false


func _initialize() -> void:
	# root ещё не в дереве: узлы собираем на первом кадре (иначе get_path/set_multiplayer не работают)
	Engine.max_fps = 60  # без экрана кадры иначе не ограничены, и «кадров» не хватило бы до конца замера
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--nodes="):
			_n_nodes = int(a.trim_prefix("--nodes="))
		elif a.begins_with("--bots="):
			_n_bots = int(a.trim_prefix("--bots="))
		elif a.begins_with("--seconds="):
			_seconds = float(a.trim_prefix("--seconds="))
		elif a.begins_with("--occupied="):
			_occupied = int(a.trim_prefix("--occupied="))
		elif a.begins_with("--port="):
			_port = int(a.trim_prefix("--port="))
	_n_nodes = maxi(_n_nodes, 1)
	if _occupied <= 0:
		_occupied = ceili(_n_nodes * 2.0 / 3.0)
	_occupied = clampi(_occupied, 1, _n_nodes)


func _build() -> void:
	_built = true
	var sroot := Node.new()
	sroot.name = "S"
	root.add_child(sroot)
	set_multiplayer(SceneMultiplayer.new(), sroot.get_path())
	var cfg := NetConfig.new()
	cfg.port = _port
	var tokens := {}
	for i in _n_bots:
		tokens["tok%d" % i] = "s_bot%d" % i
	_server = NetServer.new()
	sroot.add_child(_server)
	if _server.start(cfg, DictTokenVerifier.new(tokens)) != OK:
		printerr("bench: не удалось открыть порт %d" % _port)
		_done = true
		quit(1)
		return
	for k in _n_nodes:
		var gn := GrayNode.new()
		gn.name = "Node%02d" % (k + 1)
		gn.node_id = "node_%02d" % (k + 1)
		gn.ice_settings = {"sight_range": 0.5}  # ICE бодрствует и ходит по патрулю, но боты у входа ему неинтересны
		sroot.add_child(gn)
		gn.start(_server)
		if k % 2 == 1 and gn.ices().size() > 1:  # нечётные узлы: 1 ICE
			var extra: IceNode = gn.ices().pop_back()
			extra.queue_free()
		_nodes.append(gn)
		_w_totals.append(0)
		_w_counts.append(0)
	for i in _n_bots:
		_server.set_node("s_bot%d" % i, "node_%02d" % (i % _occupied + 1))
		var croot := Node.new()
		croot.name = "C%d" % i
		root.add_child(croot)
		set_multiplayer(SceneMultiplayer.new(), croot.get_path())
		var c := NetConfig.new()
		c.port = _port
		c.token = "tok%d" % i
		var bot := BotClient.new()
		bot.loiter_center = Vector3(-6.0 + (i % 10) * 1.2, 0, -2.0)
		bot.loiter_omega = 0.8 + 0.1 * (i % 10)
		croot.add_child(bot)
		bot.start(c, BotClient.Scenario.LOITER)
		_bots.append(bot)
	var ices := 0
	for gn in _nodes:
		ices += gn.ices().size()
	print("bench start nodes=%d (занято %d, пустых %d) ice=%d bots=%d seconds=%.0f godot=%s" % [
		_n_nodes, _occupied, _n_nodes - _occupied, ices, _n_bots, _seconds, Engine.get_version_info().string])


func _process(delta: float) -> bool:
	if _done:
		return true
	if not _built:
		_build()
		return _done
	_t += delta
	_frames += 1
	_w_frames += 1
	# работа кадра (не стенные часы: max_fps 60 держит 16.7 мс всегда): _process + физика, мс
	_w_frame_ms += (Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
	if _t >= _next_report:
		_report()
		_next_report += REPORT_SEC
	if _t >= _seconds:
		_finish()
	return _done


func _snapshot() -> Dictionary:
	# За окно: сумма времени шагов всех узлов на один физический тик и наибольший одиночный шаг узла (с начала замера).
	var tick_us := 0.0
	var ticks := 0
	var max_us := 0
	for k in _nodes.size():
		var st := _nodes[k].step_stats()
		var total: int = int(st["avg_us"]) * int(st["count"])
		var cnt: int = int(st["count"])
		tick_us += float(total - _w_totals[k])
		ticks = maxi(ticks, cnt - _w_counts[k])
		_w_totals[k] = total
		_w_counts[k] = cnt
		max_us = maxi(max_us, int(st["max_us"]))
	_step_max_all = maxi(_step_max_all, max_us)
	return {"avg_us": tick_us / maxf(ticks, 1), "max_us": max_us}


func _report() -> void:
	var s := _snapshot()
	var dt := _t - _w_t
	var kbps := float(_server.bytes_sent_total - _w_bytes) * 8.0 / 1000.0 / maxf(dt, 0.001)
	var frame_ms := _w_frame_ms / maxf(_w_frames, 1)
	print("bench t=%.0f nodes=%d bots=%d step_avg_us=%.0f step_max_us=%d frame_avg_ms=%.2f mem_mb=%.1f sent_kbps=%.1f" % [
		_t, _n_nodes, _bots.size(), s["avg_us"], s["max_us"], frame_ms, OS.get_static_memory_usage() / 1048576.0, kbps])
	_all_frames += _w_frames
	_all_frame_ms += _w_frame_ms
	_w_frames = 0
	_w_frame_ms = 0.0
	_w_bytes = _server.bytes_sent_total
	_w_t = _t


func _finish() -> void:
	_done = true
	_all_frames += _w_frames
	_all_frame_ms += _w_frame_ms
	var connected := 0
	for b in _bots:
		if b.net != null and b.net.is_connected_to_world:
			connected += 1
	var awake := 0
	for gn in _nodes:
		if _server.sessions_in(gn.node_id).size() > 0:
			awake += 1
	var avg_kbps := float(_server.bytes_sent_total) * 8.0 / 1000.0 / maxf(_t, 0.001)
	print("bench ИТОГ t=%.1f nodes=%d bots=%d подключено=%d узлов_с_игроками=%d step_max_us=%d frame_avg_ms=%.2f mem_mb=%.1f sent_kbps_avg=%.1f" % [
		_t, _n_nodes, _n_bots, connected, awake, _step_max_all, _all_frame_ms / maxf(_all_frames, 1),
		OS.get_static_memory_usage() / 1048576.0, avg_kbps])
	_server.stop_net()
	quit(0)
