#!/usr/bin/env python3
"""Отчёт по прогону П9 (Серверная HARD 8x8 или 10x10): см. p9_report.sh. Только стандартная библиотека.

Читает журнал сервера стенда (server.log; строки с меткой времени `@<секунды> ` ставит srv_p9.sh) и, если рядом есть журнал клиента
(netrun-*.log: очки — pico-logs-*/app-logs/, плоская сборка — папка попытки RunJournal), добавляет строку клиента. Чего в журнале нет — так и пишет,
ничего не выдумывает."""
import glob
import json
import os
import re
import sys

NODE = "node_05"
LAYOUTS = {8: "server_room", 10: "server_room_hard10"}
ALARM_AT = [25.0, 50.0, 75.0, 100.0]   # shared/alarm_levels.gd: уровни 1..4

TS = re.compile(r"^@(\d+(?:\.\d+)?) (.*)$")
RE_ENTER = re.compile(r"\[gray-node\] (\S+) вошёл в (node_\d+)")
RE_GRAPH = re.compile(r"\[graph\] (\S+): (node_\d+) -> (node_\d+)")
RE_EXIT = re.compile(r"\[netrun-server\] выход (\S+):")
RE_TICK = re.compile(r"^\[tick\] n=(\d+)")
RE_HOP = re.compile(r"\[netrun-server\] teleport ok ")
RE_HOP_NO = re.compile(r"\[netrun-server\] teleport denied \S+ reason=(\S+)")
RE_REQ = re.compile(r'breach\.request session=\S+ vault=(\S+) daemons=("[^"]*"|\S*) codes=(\d+)')
RE_NO = re.compile(r"breach\.no session=\S+ reason=(\S*)")
RE_TAKE = re.compile(r"\[netrun-server\] \S+ взял (node_\d+_pk(\d+))")
RE_ICE = re.compile(r"^\[ice\] t=([\d.]+) (\S+) (.+?)(?: aw=[\d.]+)? alert=([\d.]+)")
RE_EJECT = re.compile(r"ВЫБРОС (\S+)")
RE_ALARM = re.compile(r"alarm\.level node=(node_\d+) level=(\d+) alarm=([\d.]+)")
RE_SIZE = re.compile(r"srv_p9: Серверная HARD (\d+)x(\d+)")
RE_RESERVE = re.compile(r"^\[reserve\] \S+ вышел из будки")
RE_SEEN = re.compile(r"^\[(beacon|sensor)\] ")


def level_for(alarm):
    lv = 0
    for i, at in enumerate(ALARM_AT):
        if alarm >= at:
            lv = i + 1
    return lv


def fmt_t(sec):
    return "%.0f с" % sec if sec is not None else "— (нет меток)"


def parse_server(path):
    ev = {"size": None, "enter": None, "leave": None, "last": None, "stamped": False, "hops": [], "hop_no": {}, "reqs": [], "denied": 0,
          "takes": [], "ejects": [], "alarm": [], "ice_alert_max": 0.0, "reserve": 0, "seen": 0, "flatline": 0, "ice_events": 0,
          "first_tick": None, "last_tick": None}
    cur = None
    tick = 0
    base = None   # такты у каждого узла свои: считаем от первого такта после входа в node_05
    quiet_since_hop = True   # со времени последнего прыжка событий нет
    with open(path, encoding="utf-8", errors="replace") as f:
        for raw in f:
            line = raw.rstrip("\n")
            ts = None
            m = TS.match(line)
            if m:
                ts = float(m.group(1))
                line = m.group(2)
                ev["stamped"] = True
            if ts is not None:
                ev["last"] = ts
            ms = RE_SIZE.search(line)
            if ms:
                ev["size"] = int(ms.group(1))
            m = RE_TICK.match(line)
            if m and cur == NODE and ev["leave"] is None:
                n = int(m.group(1))
                if base is None:
                    base = n - 1
                tick = n - base
                ev["last_tick"] = tick
            m = RE_ENTER.search(line)
            if m:
                cur = m.group(2)
                if cur == NODE and ev["enter"] is None:
                    ev["enter"] = {"ts": ts, "tick": 0}
                    ev["first_tick"] = 0
                    tick = 0
                continue
            m = RE_GRAPH.search(line)
            if m and m.group(2) == NODE and ev["leave"] is None and ev["enter"] is not None:
                ev["leave"] = {"ts": ts, "tick": tick}
            m = RE_EXIT.search(line)
            if m and cur == NODE and ev["leave"] is None and ev["enter"] is not None:
                ev["leave"] = {"ts": ts, "tick": tick}
            if cur != NODE:
                continue
            if ev["leave"] is not None:
                continue
            if RE_HOP.search(line):
                ev["hops"].append({"ts": ts, "tick": tick, "quiet": True})
                continue
            m = RE_HOP_NO.search(line)
            if m:
                ev["hop_no"][m.group(1)] = ev["hop_no"].get(m.group(1), 0) + 1
                continue
            m = RE_REQ.search(line)
            if m:
                ds = m.group(2).strip('"')
                ev["reqs"].append({"vault": m.group(1), "tools": bool(ds), "ts": ts, "tick": tick})
                if ev["hops"]:
                    ev["hops"][-1]["quiet"] = False
                continue
            if RE_NO.search(line):
                ev["denied"] += 1
                continue
            m = RE_TAKE.search(line)
            if m:
                ev["takes"].append({"vault": m.group(1), "k": int(m.group(2)), "ts": ts, "tick": tick})
                if ev["hops"]:
                    ev["hops"][-1]["quiet"] = False
                continue
            m = RE_ICE.match(line)
            if m:
                ev["ice_events"] += 1
                ev["ice_alert_max"] = max(ev["ice_alert_max"], float(m.group(4)))
                if ev["hops"]:
                    ev["hops"][-1]["quiet"] = False
                me = RE_EJECT.search(line)
                if me:
                    ev["ejects"].append({"ts": ts, "tick": tick, "reason": me.group(1), "ice": m.group(2)})
                continue
            if RE_SEEN.match(line):
                ev["seen"] += 1
                if ev["hops"]:
                    ev["hops"][-1]["quiet"] = False
                continue
            if RE_RESERVE.match(line):
                ev["reserve"] += 1
                continue
            m = RE_ALARM.search(line)
            if m and m.group(1) == NODE:
                ev["alarm"].append({"level": int(m.group(2)), "alarm": float(m.group(3)), "ts": ts, "tick": tick})
                continue
            if "flatline" in line and line.startswith("[gray-node]"):
                ev["flatline"] += 1
    return ev


def layout_rings(size):
    name = LAYOUTS.get(size)
    if name is None:
        return None
    p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "layouts", name + ".json")
    try:
        with open(p, encoding="utf-8") as f:
            return [str(v.get("ring", "outer")) for v in json.load(f)["vaults"]]
    except (OSError, ValueError, KeyError):
        return None


def since(ev, mark):
    """Секунды и такты от входа до события mark ({ts, tick}); None — меток нет."""
    e = ev["enter"]
    sec = None if (mark["ts"] is None or e["ts"] is None) else mark["ts"] - e["ts"]
    return sec, mark["tick"] - e["tick"]


def report_server(path):
    ev = parse_server(path)
    out, missing = [], []
    if ev["enter"] is None:
        return ["нет в журнале: вход в %s (нет строки «вошёл в %s»; журнал не того стенда?)" % (NODE, NODE)], 1
    size = ev["size"]
    if size is None:
        missing.append("размер раскладки (нет строки srv_p9 «Серверная HARD NxN» — сервер запущен не srv_p9.sh)")
    rings = layout_rings(size) if size else None
    head = "Серверная HARD %s (%s)" % ("%dx%d" % (size, size) if size else "размер не известен", LAYOUTS.get(size, "?") if size else "?")
    end = ev["leave"] or {"ts": ev["last"], "tick": ev["last_tick"] if ev["last_tick"] is not None else ev["enter"]["tick"]}
    total_s = None if end["ts"] is None or ev["enter"]["ts"] is None else end["ts"] - ev["enter"]["ts"]
    total_t = end["tick"] - ev["enter"]["tick"]
    if not ev["stamped"]:
        missing.append("время в секундах (server.log без меток «@сек»: сервер запущен не srv_p9.sh); ниже — только такты")
    out.append("%s; на узле всего %s, %d тактов%s" % (head, fmt_t(total_s), total_t, "" if ev["leave"] else " (до конца журнала, узел не покидали)"))

    # время до первого взлома и первого хранилища
    first_req = since(ev, ev["reqs"][0]) if ev["reqs"] else None
    first_take = since(ev, ev["takes"][0]) if ev["takes"] else None
    out.append("до первого взлома: %s; до первого хранилища: %s" % (
        "%s (такт +%d)" % (fmt_t(first_req[0]), first_req[1]) if first_req else "не было",
        "%s (такт +%d)" % (fmt_t(first_take[0]), first_take[1]) if first_take else "не взято"))

    # прыжки
    hops = ev["hops"]
    empty = [h["quiet"] for h in hops]
    run = best = 0
    for q in empty:
        run = run + 1 if q else 0
        best = max(best, run)
    denied_hops = ", ".join("%s %d" % (k, v) for k, v in sorted(ev["hop_no"].items())) or "0"
    out.append("прыжки: %d, отказов: %s; «пустых» (после прыжка до следующего ни ICE, ни Маяка/Датчика, ни взлома): %d, макс. серия подряд %d" % (
        len(hops), denied_hops, sum(1 for q in empty if q), best))
    missing.append("видимость на каждом прыжке (видел ли ICE игрока, не среагировав): в журнале только переходы состояния ICE")

    # поимки и тревога
    ej = ", ".join("%s %s" % (e["ice"], e["reason"]) for e in ev["ejects"]) or "нет"
    out.append("поимки (ВЫБРОС): %d [%s]; флэтлайн: %d" % (len(ev["ejects"]), ej, ev["flatline"]))
    if ev["alarm"]:
        lv = max(a["level"] for a in ev["alarm"])
        seq = ", ".join("%d@+%s" % (a["level"], fmt_t(since(ev, a)[0])) if a["ts"] is not None else "%d@т+%d" % (a["level"], since(ev, a)[1]) for a in ev["alarm"])
        out.append("тревога: макс. уровень %d; смены: %s; запасной Страж вышел: %d раз" % (lv, seq, ev["reserve"]))
    else:
        lv = level_for(ev["ice_alert_max"] * 100.0)
        out.append("тревога: смен уровня в журнале нет; по строкам [ice] макс. alert %.2f (≈ уровень %d); запасной Страж вышел: %d раз" % (
            ev["ice_alert_max"], lv, ev["reserve"]))
        missing.append("смены уровня тревоги (alarm.level на сервере — только в сборке после этой ветки; здесь оценка по [ice])")

    # взломы
    reqs, takes = ev["reqs"], ev["takes"]
    started = len(reqs) - ev["denied"]
    inner_k = {i for i, r in enumerate(rings) if r == "inner"} if rings else None

    def ring_of(vault):
        k = int(vault.rsplit("_pk", 1)[1])
        return None if inner_k is None else ("внутр." if k in inner_k else "внеш.")

    cnt = {"внеш.": [0, 0], "внутр.": [0, 0], None: [0, 0]}
    for r in reqs:
        cnt[ring_of(r["vault"])][0] += 1
    for t in takes:
        cnt[ring_of(t["vault"])][1] += 1
    tools = sum(1 for r in reqs if r["tools"])
    parts = ["запросов %d (отказов сервера %d, начато ≈%d), взято хранилищ %d, не закончилось взятием ≈%d" % (
        len(reqs), ev["denied"], started, len(takes), max(started - len(takes), 0))]
    if inner_k is not None:
        parts.append("внешние: запросов %d / взято %d; внутреннее: запросов %d / взято %d" % (
            cnt["внеш."][0], cnt["внеш."][1], cnt["внутр."][0], cnt["внутр."][1]))
    elif size:
        missing.append("внешние/внутреннее (нет файла раскладки data/layouts для размера %d)" % size)
    parts.append("с демонами %d, без демонов %d" % (tools, len(reqs) - tools))
    out.append("взломы: " + "; ".join(parts))
    missing.append("итог каждого взлома (успех/обрыв) на сервере не пишется — «взял» только на успехе; точно — breach.end в журнале клиента")
    out.append("Маяк/Датчик сработали: %d раз" % ev["seen"])
    out.append("нет в журнале: " + "; ".join(missing))
    return out, 0


def client_extra(base):
    """Строка по журналу клиента рядом с server.log: новейший netrun-*.log с входом в node_05."""
    files = sorted(glob.glob(os.path.join(base, "**", "netrun-*.log"), recursive=True), key=lambda p: os.path.getmtime(p))
    for path in reversed(files):
        enter = None
        starts = won = lost = 0
        alarm = 0
        stow = None
        summary = ""
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                m = re.match(r"t=(\d+) (\S+)(.*)", line)
                if not m:
                    continue
                t, name, rest = int(m.group(1)), m.group(2), m.group(3)
                if name == "graph.node" and ("node=" + NODE) in rest and enter is None:
                    enter = t
                if enter is None:
                    continue
                if name == "breach.start":
                    starts += 1
                elif name == "breach.end":
                    mo = re.search(r"opened=(\d+)", rest)
                    if mo and int(mo.group(1)) > 0:
                        won += 1
                    else:
                        lost += 1
                elif name == "alarm.level" and ("node=" + NODE) in rest:
                    mo = re.search(r"level=(\d+)", rest)
                    alarm = max(alarm, int(mo.group(1))) if mo else alarm
                elif name == "shard.stowed" and stow is None:
                    stow = (t - enter) / 1000.0
                elif name == "run.summary":
                    summary = rest.strip()
        if enter is not None:
            return "клиент (%s): взломов начато %d, открыто %d, прервано/провал %d; до первого шарда в сумке %s; макс. уровень тревоги %d%s" % (
                os.path.basename(path), starts, won, lost, fmt_t(stow) if stow is not None else "не взят", alarm,
                "; run.summary: " + summary if summary else "")
    return None


def main(argv):
    if len(argv) != 2:
        print("использование: p9_report.sh <каталог прогона | server.log>", file=sys.stderr)
        return 2
    target = argv[1]
    if os.path.isdir(target):
        server = os.path.join(target, "server.log")
        base = target
    else:
        server, base = target, os.path.dirname(os.path.abspath(target))
    if not os.path.isfile(server):
        print("p9_report: нет server.log в %s" % target, file=sys.stderr)
        return 2
    lines, rc = report_server(server)
    print("П9 %s" % server)
    for ln in lines:
        print(ln)
    extra = client_extra(base)
    if extra:
        print(extra)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv))
