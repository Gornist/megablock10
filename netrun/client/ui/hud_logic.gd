class_name HudLogic
extends RefCounted
## Чистая логика интерфейса в мире: цвет/текст уровня trace, форматирование перезарядки, «видна ли точка».
## Без узлов и времени. Порог уровней — как в server/trace (25/50/75), клиент server/ не читает: придут с сервера.

const LEVEL_NORMAL := 0
const LEVEL_SUSPICIOUS := 1
const LEVEL_TRACE := 2
const LEVEL_LOCKDOWN := 3
const LEVEL_FLATLINE := 4

const DEFAULT_THRESHOLDS := {"suspicious_at": 25.0, "trace_at": 50.0, "lockdown_at": 75.0, "max": 100.0}

## Слои палитры клиента (AssetMaterials.LAYERS) по уровням trace: цвет задаёт Blender, здесь только соответствие.
const LEVEL_LAYERS := ["hud_ok", "hud_notice", "hud_warn", "hud_bad", "hud_off"]
const LEVEL_NAMES := ["спокойно", "подозрение", "трассировка", "блокировка", "обрыв"]


static func level_from_value(value: float, thresholds: Dictionary = DEFAULT_THRESHOLDS) -> int:
	if value >= float(thresholds.get("max", 100.0)):
		return LEVEL_FLATLINE
	if value >= float(thresholds.get("lockdown_at", 75.0)):
		return LEVEL_LOCKDOWN
	if value >= float(thresholds.get("trace_at", 50.0)):
		return LEVEL_TRACE
	if value >= float(thresholds.get("suspicious_at", 25.0)):
		return LEVEL_SUSPICIOUS
	return LEVEL_NORMAL


static func level_color(level: int) -> Color:
	return AssetMaterials.layer(LEVEL_LAYERS[clampi(level, 0, LEVEL_LAYERS.size() - 1)])


static func level_name(level: int) -> String:
	return LEVEL_NAMES[clampi(level, 0, LEVEL_NAMES.size() - 1)]


## Доля заполнения полосы 0..1.
static func trace_fraction(value: float, max_value: float = 100.0) -> float:
	if max_value <= 0.0:
		return 0.0
	return clampf(value / max_value, 0.0, 1.0)


static func trace_text(value: float, level: int) -> String:
	return "%s %d" % [level_name(level), roundi(value)]


## Перезарядка: 0 → «готово», до минуты — «N с» (вверх, чтобы не показывать «0 с» при ещё идущей), дальше — «м:сс».
static func cooldown_text(remaining_sec: float) -> String:
	if remaining_sec <= 0.0:
		return "готово"
	var s := ceili(remaining_sec)
	if s < 60:
		return "%d с" % s
	return "%d:%02d" % [s / 60, s % 60]


## Видна ли точка камере: point — в мире, cam — глобальный Transform3D камеры (взгляд в -Z).
## fov_v_deg — вертикальный угол обзора, aspect — ширина/высота. Позади камеры — не видна.
static func is_point_visible(cam: Transform3D, point: Vector3, fov_v_deg: float, aspect: float) -> bool:
	var l := cam.affine_inverse() * point
	if l.z >= 0.0:
		return false
	var depth := -l.z
	var ty := tan(deg_to_rad(fov_v_deg) * 0.5)
	return absf(l.y / depth) <= ty and absf(l.x / depth) <= ty * aspect


## Направление на экране (x вправо, y вверх, длина 1) на точку в системе камеры. Ровно по оси взгляда — вверх.
static func edge_direction(cam: Transform3D, point: Vector3) -> Vector2:
	var l := cam.affine_inverse() * point
	var d := Vector2(l.x, l.y)
	if d.length() < 0.0001:
		return Vector2.UP
	return d.normalized()


## Человеческая подпись эффекта демона (одна короткая строка на деке); неизвестный эффект показывается как есть.
const EFFECT_TITLES := {
	"GHOST": "невидим для ICE", "JITTER": "trace замирает", "EXTRACT_SHARD": "достать шард", "EXTRACT_DAEMON": "достать демона",
	"TIMESKEW": "сигнал СБ позже", "BLACKOUT": "сигнал СБ не уйдёт", "DECRYPT": "расшифровка", "MINER": "добыча эдди",
}

## Состояние программы (st из state.cd сервера): готов / перезарядка N / активен N с / не работает в Сети; для защитных демонов, которые вне взлома
## срабатывают только заряженными (chargeable, К6), «готов» значит «не заряжен», а st = charged — «ГОТОВ К ЗАПУСКУ». Без st (старый снимок, только
## перезарядка) — как раньше: «готово» или «N с».
static func state_text(st: String, cooldown_left: float, active_left: float = 0.0, chargeable: bool = false) -> String:
	match st:
		"ready":
			return "не заряжен" if chargeable else "готов"
		"charged":
			return "ГОТОВ К ЗАПУСКУ"
		"cooldown":
			return "перезарядка " + cooldown_text(cooldown_left)
		"active":
			return "активен " + cooldown_text(active_left)
		"unsupported":
			return "не работает в Сети"
	return cooldown_text(cooldown_left)


## Тон состояния для цвета строки: ok (готов, заряжен), warn (перезарядка), acc (активен), dim (не работает, не заряжен).
static func state_tone(st: String, cooldown_left: float, chargeable: bool = false) -> String:
	match st:
		"active":
			return "acc"
		"cooldown":
			return "warn"
		"unsupported":
			return "dim"
		"charged":
			return "ok"
		"ready":
			return "dim" if chargeable else "ok"
	return "ok" if cooldown_left <= 0.0 else "warn"


## Нужно ли показать у программы кнопку «ЗАРЯДИТЬ»: защитный демон, поддержанный в Сети, не заряжен, не на перезарядке и не действует.
static func can_charge(st: String, chargeable: bool) -> bool:
	return chargeable and st == "ready"


## Плашка над списком программ, если есть заряженные: заряд — ещё не эффект, его надо включить (повтор П1: заряженного Призрака приняли за
## включённого). VR — левый X (rig_test_scene.use_selected: выбранного, если он заряжен, иначе первого заряженного); плоская сборка — цифра слота.
const LAUNCH_HINT := "ЗАРЯЖЕН · включить: левый X"


## Плашка над списком программ, пока действует эффект демона: «ДЕЙСТВУЕТ 12 с · 1 Призрак · невидим для ICE». row — строка deck_rows.
static func active_banner(row: Dictionary) -> String:
	var text := "ДЕЙСТВУЕТ %s · %s" % [cooldown_text(float(row.get("active_left", 0.0))), str(row.get("name", ""))]
	var effect := str(row.get("effect", ""))
	return text if effect == "" else text + " · " + effect


## Поля строки журнала `breach.end` (взлом хранилища): итог, досрочность, эдди, сколько хранилищ открыто, ошибка Моста и — для разбора замка — `lock_opened`
## (1 — замок вскрыт, 0 — нет) и `matched_before_lock` (id через запятую: совпали до вскрытия, не засчитаны). Сервер без этих полей (старый) — 0 и пусто.
static func breach_end_fields(ev: Dictionary) -> Dictionary:
	var before: Array = ev.get("matched_before_lock", [])
	return {"outcome": ev.get("outcome", ""), "early": ev.get("early", ""), "eddies": ev.get("eddies", 0), "opened": (ev.get("opened", []) as Array).size(),
		"error": ev.get("error", ""), "lock_opened": 1 if bool(ev.get("lock_opened", false)) else 0,
		"matched_before_lock": ",".join(PackedStringArray(before.map(func(i): return str(i))))}


## Поля строки журнала `breach.request` (одна строка): хранилище, демоны (число и id), сумма кодов их цепочек, RAM деки и длина замка тира —
## по ним видно, почему сервер ответил bad_daemons («замок + коды > RAM»). daemons — рабочие демоны деки (ev deck: id, cells).
static func breach_request_fields(vault: String, ids: Array, daemons: Array, ram: int, lock: int) -> Dictionary:
	var codes := 0
	for d in daemons:
		if ids.has(str(d.get("id", ""))):
			codes += (d.get("cells", []) as Array).size()
	return {"vault": vault, "daemons": ids.size(), "ids": ",".join(PackedStringArray(ids.map(func(i): return str(i)))), "codes": codes, "ram": ram, "lock": lock}


## Поля строки `daemon.use` по ответу сервера (`daemon {daemon, ok, error?, reason?}`): phase = ok или denied с причиной.
static func daemon_result_fields(ev: Dictionary) -> Dictionary:
	if bool(ev.get("ok", false)):
		return {"phase": "ok", "daemon": str(ev.get("daemon", ""))}
	var out := {"phase": "denied", "daemon": str(ev.get("daemon", "")), "error": str(ev.get("error", ""))}
	if ev.has("reason"):
		out["reason"] = str(ev["reason"])
	return out


## Начало и конец действия эффектов по снимкам (`state.cd`, k — время сервера): prev — id, что были active в прошлом снимке.
## Возвращает {active: новый набор, started: [{id, left}], ended: [id]}.
static func effect_edges(prev: Dictionary, cd: Array, k: float) -> Dictionary:
	var active := {}
	var started: Array = []
	for c in cd:
		var id := str(c.get("id", ""))
		if str(c.get("st", "")) == "active":
			active[id] = true
			if not prev.has(id):
				started.append({"id": id, "left": snappedf(maxf(float(c.get("until", k)) - k, 0.0), 0.1)})
	var ended: Array = []
	for id in prev:
		if not active.has(id):
			ended.append(id)
	return {"active": active, "started": started, "ended": ended}


## Текст отказа запуска (`daemon {ok: false, error}`) для строки-уведомления на деке.
static func launch_error_text(error: String) -> String:
	match error:
		"not_charged":
			return "Не заряжен: нажмите ЗАРЯДИТЬ"
		"cooldown":
			return "Перезарядка"
		"effect_unsupported":
			return "В Сети не работает"
		"not_in_deck", "unknown_daemon":
			return "Нет такой программы"
	return "Нельзя запустить"


## Отказ заряда (`bk_no` с mode = charge) словами для строки-уведомления на деке.
static func charge_denied_text(reason: String, left: int = 0) -> String:
	match reason:
		"active":
			return "Сейчас идёт другая мини-игра"
		"charging":
			return "Идёт заряд"
		"cooldown":
			return "Перезарядка: %s" % cooldown_text(float(left))
		"charged":
			return "Уже заряжен"
		"not_chargeable":
			return "Этот демон не заряжается"
		"bad_daemon":
			return "У демона нет цепочки"
	return "Сейчас нельзя"


## Цепочка кодов демона строкой для моноширинного шрифта: «1C BD E9».
static func chain_text(cells: Array) -> String:
	return " ".join(PackedStringArray(cells.map(func(c: Variant) -> String: return str(c))))


## Шкала RAM: {text «занято/ёмкость», fraction 0..1, over — занято больше ёмкости, default — ёмкость условная}. ram <= 0 — шкалы нет (null).
static func ram_view(ram: int, used: int, ram_default: bool = false) -> Variant:
	if ram <= 0:
		return null
	return {"text": "%d/%d" % [used, ram], "fraction": clampf(float(used) / float(ram), 0.0, 1.0), "over": used > ram, "default": ram_default}


## Рабочие демоны для деки: строки перезарядок из state.cd ({id, name, left, st?, until?}) плюс свойства из ev deck (info — его daemons:
## tier, cells, effect, unsupported). Нет свойств у демона или события вовсе — остаются только поля снимка. k — время сервера в снимке:
## оно нужно, чтобы превратить until в «осталось N с» без общих часов. Добытые демоны (loaded == false) в рабочие не попадают.
static func program_entries(cd: Array, info: Array, k: float) -> Array:
	var by_id := {}
	for d in info:
		by_id[str(d.get("id", ""))] = d
	var out := []
	for c in cd:
		var id := str(c.get("id", ""))
		var meta: Dictionary = by_id.get(id, {})
		if not bool(meta.get("loaded", true)):
			continue
		var st := str(c.get("st", ""))
		var left := float(c.get("left", 0.0))
		var entry := {"id": id, "name": str(c.get("name", id)), "cooldown_left": left}
		if st != "":
			entry["st"] = st
			if st == "active":
				entry["active_left"] = maxf(0.0, float(c.get("until", k)) - k)
		for key in ["tier", "cells", "effect", "unsupported", "chargeable"]:
			if meta.has(key):
				entry[key] = meta[key]
		out.append(entry)
	return out


## Список демонов деки → строки панели: [{"text", "selected", "ready", ...}]. Демон: id, name, cooldown_left; необязательно st, active_left,
## tier, cells, effect, unsupported. text — «имя  состояние» (то, что видно в первой строке плашки), остальное — для остальных строк.
static func deck_rows(deck: Dictionary) -> Array:
	var rows := []
	var selected := str(deck.get("selected", ""))
	for d in deck.get("daemons", []):
		var left := float(d.get("cooldown_left", 0.0))
		var st := str(d.get("st", ""))
		var chargeable := bool(d.get("chargeable", false))
		var state := state_text(st, left, float(d.get("active_left", 0.0)), chargeable)
		var name := str(d.get("name", d.get("id", "?")))
		var effect := str(d.get("effect", ""))
		rows.append({
			"text": "%s  %s" % [name, state],
			"name": name,
			"state": state,
			"tone": state_tone(st, left, chargeable),
			"id": str(d.get("id", "")),
			"chargeable": chargeable,
			"charged": st == "charged",
			"active": st == "active",
			"active_left": ceili(float(d.get("active_left", 0.0))),   # целые секунды: ключ перерисовки деки не должен меняться на каждом снимке
			"can_charge": can_charge(st, chargeable),
			"selected": str(d.get("id", "")) == selected,
			"ready": left <= 0.0 and st != "unsupported",
			"tier": int(d.get("tier", 0)),
			"chain": chain_text(d.get("cells", [])),
			"effect": EFFECT_TITLES.get(effect, effect),
		})
	return rows


## Добыча для вкладки ДОБЫЧА: [{text, kind, kind_name, title, tier, enc, label}] из ev deck.loot ({id, kind: shard | daemon, tier, title, enc}).
## label у демона с известным эффектом — «В ГРУЗЕ», в text его эффект, в строке chain (К8).
## daemons — рабочие демоны деки из того же события ({effect, tier, ...}): по ним решается, есть ли у зашифрованного шарда кнопка «РАСШИФРОВАТЬ» (can_decrypt, К7).
static func loot_rows(loot: Array, daemons: Array = []) -> Array:
	var rows := []
	for l in loot:
		var kind := str(l.get("kind", "shard"))
		var enc := bool(l.get("enc", false))
		var title := str(l.get("title", "?"))
		var tier := int(l.get("tier", 0))
		var kind_name := "ДЕМОН" if kind == "daemon" else "ШАРД"
		var label := "ЗАШИФРОВАН" if enc else "ОТКРЫТ"
		var effect := str(l.get("effect", ""))
		var cells: Variant = l.get("cells")
		var chain := chain_text(cells) if cells is Array else ""
		var text := "%s  %s  тир %d  %s" % [kind_name, title, tier, label]
		if kind == "daemon" and effect != "":
			# Добытый демон: «ДЕМОН · тир · эффект» и цепочка кодов; в забеге не работает, до выхода лежит в грузе.
			label = "В ГРУЗЕ"
			text = "%s  %s  тир %d  %s" % [kind_name, title, tier, EFFECT_TITLES.get(effect, effect)]
		rows.append({"id": str(l.get("id", "")), "text": text, "kind": kind, "kind_name": kind_name, "title": title, "tier": tier, "enc": enc, "label": label,
			"give": bool(l.get("give", false)), "effect": EFFECT_TITLES.get(effect, effect), "chain": chain,
			"can_decrypt": kind == "shard" and enc and not DeckDecrypt.best(daemons, tier).is_empty(),
			"no_decrypter": kind == "shard" and enc and DeckDecrypt.best(daemons, tier).is_empty()})
	return rows


# ---------------------------------------------------------------- расшифровка шарда (К7)

## Отказ расшифровки (`bk_no` с mode = decrypt) словами для строки-уведомления на деке.
static func decrypt_denied_text(reason: String) -> String:
	match reason:
		"active":
			return "Сейчас идёт другая мини-игра"
		"no_decrypter":
			return "Нужен рабочий DECRYPT не ниже тира шарда"
		"open":
			return "Шард уже открыт"
		"not_shard":
			return "Расшифровать можно только шард"
		"gone":
			return "Шарда уже нет в деке"
		"no_bridge":
			return "Сеть без Моста: расшифровать нельзя"
	return "Сейчас нельзя"


## Ошибка записи в Мост после выигранной мини-игры (`bk_end` mode = decrypt, error) словами для итога.
static func decrypt_error_text(error: String) -> String:
	match error:
		"unavailable":
			return "Нет связи с Мостом: повторите"
		"gone":
			return "Шарда уже нет в деке"
		"busy":
			return "Забег закрывается"
		"no_decrypter":
			return "DECRYPT уже не работает"
	return "Мост отказал"


## Подпись под итогом расшифровки: открыт / причина.
static func decrypt_result_sub(ev: Dictionary) -> String:
	var title := str(ev.get("title", "")).strip_edges()
	if bool(ev.get("decrypted", false)):
		return "%s · теперь ОТКРЫТ" % (title if title != "" else "Шард")
	if str(ev.get("error", "")) != "":
		return decrypt_error_text(str(ev["error"]))
	if str(ev.get("early", "")) != "":
		return "Прервано"
	return "Время вышло — можно снова"


# ---------------------------------------------------------------- отправка добычи (К5б)

const GIVE_ERROR_TEXTS := {
	"not_loot": "это нельзя отдать: защищённое или рабочее",
	"no_recipient": "получателя уже нет в Сети",
	"self": "на свой телефон отдавать нельзя",
	"bad_contact": "контакт не принят: проверьте телефон в ЧАТЕ",
	"gone": "предмета уже нет в деке",
	"busy": "сейчас нельзя: у кого-то идёт выход",
	"refused": "Мост отказал",
	"unavailable": "нет связи с Мостом, попробуйте ещё раз",
	"no_bridge": "Сеть без Моста: отдавать нечего",
}


## Причина отказа отправки (WorldMsg.GIVE_ERRORS) словами для игрока.
static func give_error_text(reason: String) -> String:
	return GIVE_ERROR_TEXTS.get(reason, "не вышло (%s)" % reason)


## Получатели одним списком: [{kind: runner | phone, label, section, target, tag}]. Нетраннеры в Сети — первыми (те, кто в том же узле, —
## впереди остальных), затем контакты телефона по алфавиту. runners — из события give_list [{id, name, same}], contacts — из PhoneLink.contacts()
## [{key, title}]. target — то, что уйдёт серверу в `to`.
static func give_targets(runners: Array, contacts: Array) -> Array:
	var out := []
	var net_rows := []
	for r in runners:
		net_rows.append({"kind": WorldMsg.VIA_RUNNER, "label": str(r.get("name", "?")), "section": "В СЕТИ", "tag": "ЗДЕСЬ" if bool(r.get("same", false)) else "В СЕТИ",
			"same": bool(r.get("same", false)), "target": {"runner": int(r.get("id", 0))}})
	net_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["same"] != b["same"]:
			return a["same"]
		return a["label"] < b["label"])
	out.append_array(net_rows)
	var phone_rows := []
	for c in contacts:
		var key := str(c.get("key", ""))
		if key.is_empty():
			continue
		phone_rows.append({"kind": WorldMsg.VIA_PHONE, "label": str(c.get("title", "?")), "section": "КОНТАКТЫ ТЕЛЕФОНА", "tag": "ТЕЛЕФОН", "same": false, "target": {"phone": key}})
	phone_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["label"] < b["label"])
	out.append_array(phone_rows)
	return out


## Что спрашивает подтверждение: строка про предмет и получателя и строка про последствия (для нетраннера и для телефона они разные).
static func give_confirm_lines(row: Dictionary, target_row: Dictionary) -> Array:
	var what := "%s  %s  тир %d" % [row.get("kind_name", "ШАРД"), row.get("title", "?"), int(row.get("tier", 0))]
	if target_row.get("kind", "") == WorldMsg.VIA_PHONE:
		return [what + "  >  " + str(target_row["label"]), "Уйдёт на его телефон карточкой и покинет забег целиком. Вернуть нельзя."]
	return [what + "  >  " + str(target_row["label"]), "Сразу окажется в его ГРУЗЕ и выйдет из-под риска вашего забега. Вернуть нельзя."]


## Итоговая строка на ДОБЫЧЕ: ev give с dir out/in; to_label — как игрок назвал получателя (для телефона сервер имени не знает).
static func give_result_text(ev: Dictionary, to_label: String = "") -> String:
	var title := str(ev.get("title", "")).strip_edges()
	if str(ev.get("dir", WorldMsg.GIVE_OUT)) == WorldMsg.GIVE_IN:
		return "ПОЛУЧЕНО от %s: %s" % [ev.get("from", "?"), title if title != "" else "предмет"]
	if bool(ev.get("ok", false)):
		var who := str(ev.get("who", "")) if str(ev.get("who", "")) != "" else to_label
		return "ОТПРАВЛЕНО: %s > %s" % [title if title != "" else "предмет", who if who != "" else "получатель"]
	return "НЕ ОТПРАВЛЕНО: " + give_error_text(str(ev.get("error", "")))
