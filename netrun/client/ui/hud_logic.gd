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

const LEVEL_COLORS := [
	Color(0.2, 0.9, 0.5),
	Color(1.0, 0.85, 0.2),
	Color(1.0, 0.5, 0.15),
	Color(1.0, 0.15, 0.2),
	Color(0.6, 0.6, 0.65),
]
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
	return LEVEL_COLORS[clampi(level, 0, LEVEL_COLORS.size() - 1)]


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

## Состояние программы (st из state.cd сервера): готов / перезарядка N / активен N с / не работает в Сети. Без st (старый снимок, только
## перезарядка) — как раньше: «готово» или «N с».
static func state_text(st: String, cooldown_left: float, active_left: float = 0.0) -> String:
	match st:
		"ready":
			return "готов"
		"cooldown":
			return "перезарядка " + cooldown_text(cooldown_left)
		"active":
			return "активен " + cooldown_text(active_left)
		"unsupported":
			return "не работает в Сети"
	return cooldown_text(cooldown_left)


## Тон состояния для цвета строки: ok (готов), warn (перезарядка), acc (активен), dim (не работает).
static func state_tone(st: String, cooldown_left: float) -> String:
	match st:
		"active":
			return "acc"
		"cooldown":
			return "warn"
		"unsupported":
			return "dim"
		"ready":
			return "ok"
	return "ok" if cooldown_left <= 0.0 else "warn"


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
		for key in ["tier", "cells", "effect", "unsupported"]:
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
		var state := state_text(st, left, float(d.get("active_left", 0.0)))
		var name := str(d.get("name", d.get("id", "?")))
		var effect := str(d.get("effect", ""))
		rows.append({
			"text": "%s  %s" % [name, state],
			"name": name,
			"state": state,
			"tone": state_tone(st, left),
			"selected": str(d.get("id", "")) == selected,
			"ready": left <= 0.0 and st != "unsupported",
			"tier": int(d.get("tier", 0)),
			"chain": chain_text(d.get("cells", [])),
			"effect": EFFECT_TITLES.get(effect, effect),
		})
	return rows


## Добыча для вкладки ДОБЫЧА: [{text, kind, kind_name, title, tier, enc, label}] из ev deck.loot ({id, kind: shard | daemon, tier, title, enc}).
## label — «ОТКРЫТ» / «ЗАШИФРОВАН» (добытый демон не шифруется — у него «ОТКРЫТ»; в этом забеге он всё равно не работает).
static func loot_rows(loot: Array) -> Array:
	var rows := []
	for l in loot:
		var kind := str(l.get("kind", "shard"))
		var enc := bool(l.get("enc", false))
		var title := str(l.get("title", "?"))
		var tier := int(l.get("tier", 0))
		var kind_name := "ДЕМОН" if kind == "daemon" else "ШАРД"
		var label := "ЗАШИФРОВАН" if enc else "ОТКРЫТ"
		rows.append({"id": str(l.get("id", "")), "text": "%s  %s  тир %d  %s" % [kind_name, title, tier, label], "kind": kind, "kind_name": kind_name, "title": title, "tier": tier, "enc": enc, "label": label,
			"give": bool(l.get("give", false))})
	return rows


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
