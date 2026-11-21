class_name DotSuspicion
extends RefCounted

## A decaying suspicion score per player. Detectors (GameSpice Server Security ships speed, teleport and aim-snap ones) report what they saw; this adds it up, forgives it over time, and says which level the player has reached. It never acts: the game kicks or bans, so a wrong score costs a log line, not a good player's account.

enum Level { NONE, WARN, KICK, BAN }

var config: DotSuspicionConfig
## Players forgotten to stay inside `max_players`.
var evicted: int = 0

var _players: Dictionary = {}   # id -> {"score": float, "at": float, "level": int, "events": int}
var _weights: Dictionary = {}


func _init(p_config: DotSuspicionConfig = null) -> void:
	config = p_config if p_config != null else DotSuspicionConfig.new()
	_weights = config.weight_table()


static func level_name(level: int) -> String:
	return String(Level.keys()[level]).to_lower()


## Adds one detection for [param player_id] at [param now] (seconds). The argument order matches the detected signal of GameSpice Server Security, so it can be connected straight to a handler. Returns a DotResult whose value is {score, level, changed}.
func observe(player_id: Variant, kind: StringName, impossible: bool = false, now: float = -1.0) -> DotResult:
	if not config.enabled:
		return DotResult.success({"score": 0.0, "level": Level.NONE, "changed": false})
	var id := str(player_id)
	if id == "":
		return DotResult.fail(DotError.CODE_INVALID, "suspicion needs a player id")
	var t := _now(now)
	var p := _entry(id, t)
	_decay(p, t)
	p["score"] = float(p["score"]) + _points(kind, impossible)
	p["events"] = int(p["events"]) + 1
	_remember(p, kind, impossible, t)
	var before := int(p["level"])
	var after := _level_for(float(p["score"]))
	p["level"] = after
	return DotResult.success({"score": p["score"], "level": after, "changed": after != before})


## The score after decay; 0 for a player never seen.
func score(player_id: Variant, now: float = -1.0) -> float:
	var p: Variant = _players.get(str(player_id))
	if p == null:
		return 0.0
	_decay(p, _now(now))
	p["level"] = _level_for(float(p["score"]))
	return float(p["score"])


func level(player_id: Variant, now: float = -1.0) -> int:
	score(player_id, now)
	var p: Variant = _players.get(str(player_id))
	return Level.NONE if p == null else int(p["level"])


## Detections counted for a player since they were first seen.
func events(player_id: Variant) -> int:
	var p: Variant = _players.get(str(player_id))
	return 0 if p == null else int(p["events"])


## The newest detections of a player, oldest first, as [{kind, impossible, at}]: what a person reads before acting on a score. Bounded by `history_per_player`.
func history(player_id: Variant) -> Array:
	var p: Variant = _players.get(str(player_id))
	return [] if p == null else (p["recent"] as Array).duplicate(true)


## Clears a player's score and history after a person reviewed them (the detection count is kept).
func reset(player_id: Variant) -> void:
	var p: Variant = _players.get(str(player_id))
	if p != null:
		p["score"] = 0.0
		p["level"] = Level.NONE
		(p["recent"] as Array).clear()


## Everything tracked, as plain data a game can store: {id: {score, at, level, events, recent}}. Times are the clock's own, so only reload it where the same clock runs.
func to_dict() -> Dictionary:
	return _players.duplicate(true)


## Replaces what is tracked with [param data] from [method to_dict]. Entries with the wrong shape are skipped; the value is how many.
func load_dict(data: Dictionary) -> DotResult:
	_players.clear()
	var skipped := 0
	for id in data:
		var e: Variant = data[id]
		if e is Dictionary and e.has("score") and e.has("at") and e.has("level") and e.has("events") and e.get("recent") is Array:
			_players[str(id)] = (e as Dictionary).duplicate(true)
		else:
			skipped += 1
	return DotResult.success(skipped)


func forget(player_id: Variant) -> void:
	_players.erase(str(player_id))


func size() -> int:
	return _players.size()


## The [param n] highest scores, as [{id, score, level}], worst first. [param n] of 0 returns everyone.
func top(n: int = 10, now: float = -1.0) -> Array:
	var t := _now(now)
	var rows: Array = []
	for id in _players.keys():
		rows.append({"id": id, "score": score(id, t), "level": int(_players[id]["level"])})
	rows.sort_custom(func(a, b): return a["score"] > b["score"])
	if n > 0 and rows.size() > n:
		rows.resize(n)
	return rows


func _remember(p: Dictionary, kind: StringName, impossible: bool, t: float) -> void:
	var recent: Array = p["recent"]
	recent.append({"kind": String(kind), "impossible": impossible, "at": t})
	if config.history_per_player > 0 and recent.size() > config.history_per_player:
		recent.pop_front()


func _points(kind: StringName, impossible: bool) -> float:
	var table_hit: Variant = _weights.get(String(kind))
	if table_hit != null:
		return float(table_hit)
	return config.impossible_weight if impossible else config.default_weight


func _level_for(s: float) -> int:
	if config.ban_at > 0.0 and s >= config.ban_at:
		return Level.BAN
	if config.kick_at > 0.0 and s >= config.kick_at:
		return Level.KICK
	if config.warn_at > 0.0 and s >= config.warn_at:
		return Level.WARN
	return Level.NONE


func _decay(p: Dictionary, t: float) -> void:
	if config.decay_per_second > 0.0:
		p["score"] = maxf(0.0, float(p["score"]) - (t - float(p["at"])) * config.decay_per_second)
	p["at"] = t


func _entry(id: String, t: float) -> Dictionary:
	if _players.has(id):
		return _players[id]
	if config.max_players > 0 and _players.size() >= config.max_players:
		_evict_lowest(t)
	var p := {"score": 0.0, "at": t, "level": Level.NONE, "events": 0, "recent": []}
	_players[id] = p
	return p


func _evict_lowest(t: float) -> void:
	var worst := ""
	var low := INF
	for id in _players.keys():
		var s := score(id, t)
		if s < low:
			low = s
			worst = id
	if worst != "":
		_players.erase(worst)
		evicted += 1


func _now(now: float) -> float:
	return now if now >= 0.0 else Time.get_ticks_msec() / 1000.0
