extends Node

## dot-anticheat's headless suite (res://examples/anticheat_selftest.tscn).
## Counts sections run to their last line as well as checks, because a script error
## aborts a section and not the run.

const EXPECTED_SECTIONS := 7
const EXPECTED_CHECKS := 60

var _passed := 0
var _failed := 0
var _sections := 0
var _seen: Array = []


class FakeDetector:
	extends Node
	signal detected(session, kind, impossible, detail)


class FakeSession:
	extends RefCounted
	var player_id := "p7"


func _ready() -> void:
	print("dot-anticheat")
	_config()
	_score()
	_levels()
	_sanity()
	_watch()
	_layers()
	_review()
	print("")
	_check(_sections == EXPECTED_SECTIONS, "every section ran to its last line (%d of %d)" % [_sections, EXPECTED_SECTIONS])
	_check(_passed + _failed == EXPECTED_CHECKS, "and the suite ran all %d of its checks (%d)" % [EXPECTED_CHECKS, _passed + _failed])
	print("%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _config() -> void:
	var c := GSSuspicionConfig.new()
	_check(c.validate().ok, "defaults validate")
	_check(c.ban_at == 0.0, "banning is off unless an operator sets it")
	c.warn_at = 80.0
	_check(not c.validate().ok, "warn above kick is refused")
	c.warn_at = 20.0
	c.weights = PackedStringArray(["cheat.aim_snap=8", "bad"])
	_check(not c.validate().ok, "a weight that is not kind=number is refused")
	c.weights = PackedStringArray(["cheat.aim_snap=8"])
	_check(c.validate().ok and c.weight_table()["cheat.aim_snap"] == 8.0, "a weight table parses")
	_check(c.has_key("decay_per_second") and c.has_key("max_players") and c.has_key("max_speed"), "the tunables are config keys")
	_sections += 1


func _score() -> void:
	var s := GSSuspicion.new()
	_check(s.score("a", 0.0) == 0.0, "an unseen player scores 0")
	s.observe("a", &"cheat.speed", false, 0.0)
	s.observe("a", &"cheat.speed", false, 0.0)
	_check(is_equal_approx(s.score("a", 0.0), 2.0), "two suspicions add up")
	_check(is_equal_approx(s.score("a", 2.0), 1.0), "the score decays with time")
	_check(s.score("a", 100.0) == 0.0, "and never goes below zero")
	_check(s.events("a") == 2, "detections are counted")
	s.observe("b", &"cheat.teleport", true, 0.0)
	_check(is_equal_approx(s.score("b", 0.0), 100.0), "an impossible detection weighs the impossible weight")
	var cfg := GSSuspicionConfig.new()
	cfg.decay_per_second = 0.0
	var nd := GSSuspicion.new(cfg)
	nd.observe("c", &"x", false, 0.0)
	_check(nd.score("c", 1000.0) == 1.0, "decay 0 means the score stays")
	cfg.weights = PackedStringArray(["cheat.aim_snap=8"])
	var w := GSSuspicion.new(cfg)
	w.observe("d", &"cheat.aim_snap", false, 0.0)
	_check(w.score("d", 0.0) == 8.0, "a per-kind weight wins")
	_check(not s.observe("", &"x").ok, "an empty player id fails loudly")
	s.forget("a")
	_check(s.score("a", 0.0) == 0.0 and s.size() == 1, "forget drops a player")
	var off := GSSuspicionConfig.new()
	off.enabled = false
	var o := GSSuspicion.new(off)
	o.observe("e", &"x", true, 0.0)
	_check(o.score("e", 0.0) == 0.0 and o.size() == 0, "disabled scores nothing")
	_sections += 1


func _levels() -> void:
	var cfg := GSSuspicionConfig.new()
	cfg.decay_per_second = 0.0
	cfg.ban_at = 200.0
	var s := GSSuspicion.new(cfg)
	_check(s.level("a", 0.0) == GSSuspicion.Level.NONE, "starts at none")
	var r := s.observe("a", &"x", true, 0.0)
	_check((r.value as Dictionary)["level"] == GSSuspicion.Level.KICK and r.value["changed"], "one proof reaches kick (100 >= 60)")
	s.observe("a", &"x", true, 0.0)
	_check(s.level("a", 0.0) == GSSuspicion.Level.BAN, "ban at its own threshold")
	var def := GSSuspicion.new()
	for i in 100:
		def.observe("z", &"x", true, 0.0)
	_check(def.level("z", 0.0) == GSSuspicion.Level.KICK, "with ban_at 0 nothing ever reaches ban")
	_check(GSSuspicion.level_name(GSSuspicion.Level.WARN) == "warn", "level names")
	var d2 := GSSuspicionConfig.new()
	d2.decay_per_second = 1.0
	var dec := GSSuspicion.new(d2)
	dec.observe("a", &"x", true, 0.0)
	_check(dec.level("a", 0.0) == GSSuspicion.Level.KICK and dec.level("a", 60.0) == GSSuspicion.Level.WARN, "a level steps back down as the score decays")
	_check(dec.level("a", 100.0) == GSSuspicion.Level.NONE, "and returns to none")
	var lim := GSSuspicionConfig.new()
	lim.max_players = 2
	lim.decay_per_second = 0.0
	var l := GSSuspicion.new(lim)
	l.observe("p1", &"x", false, 0.0)
	l.observe("p2", &"x", true, 0.0)
	l.observe("p3", &"x", true, 0.0)
	_check(l.size() == 2 and l.evicted == 1 and l.score("p1", 0.0) == 0.0, "at max_players the lowest score is evicted and counted")
	var rows := l.top(1, 0.0)
	_check(rows.size() == 1 and rows[0]["score"] == 100.0, "top returns the worst first")
	var many := GSSuspicion.new(cfg)
	for i in 300:
		many.observe("m%d" % i, &"x", false, 0.0)
	_check(many.size() == 300, "max_players 0 is unlimited")
	_sections += 1


func _sanity() -> void:
	var cfg := GSSuspicionConfig.new()
	cfg.max_speed = 10.0
	cfg.max_turn_rate = 360.0
	cfg.max_command_rate = 3.0
	cfg.world_extent = 1000.0
	var c := GSCommandSanity.new(cfg)
	_check(c.check_move(Vector3.ZERO, Vector3(5, 0, 0), 1.0) == "", "a legal move passes")
	_check(c.check_move(Vector3.ZERO, Vector3(50, 0, 0), 1.0) == GSCommandSanity.SPEED, "a move too fast is speed")
	_check(c.check_move(Vector3.ZERO, Vector3(1, 0, 0), 0.0) == GSCommandSanity.SPEED, "distance in no time is speed")
	_check(c.check_move(Vector3.ZERO, Vector3(NAN, 0, 0), 1.0) == GSCommandSanity.MALFORMED, "NaN is malformed, not a crash")
	_check(c.check_move(Vector3.ZERO, Vector3(INF, 0, 0), 1.0) == GSCommandSanity.MALFORMED, "infinity is malformed")
	_check(c.check_move(Vector3.ZERO, Vector3(5000, 0, 0), 100.0) == GSCommandSanity.RANGE, "outside the world is out of range")
	_check(c.check_look(10.0, 5.0, 1.0) == "", "a normal turn passes")
	_check(c.check_look(3000.0, 0.0, 1.0) == GSCommandSanity.TURN, "a snap turn is flagged")
	_check(c.check_look(NAN, 0.0, 1.0) == GSCommandSanity.MALFORMED, "a NaN turn is malformed")
	var hit := ""
	for i in 4:
		hit = c.check_command("a", 0.1 * i)
	_check(hit == GSCommandSanity.RATE, "more than the command rate in a second is flagged")
	_check(c.check_command("a", 5.0) == "", "and the window slides")
	_check(c.check_command("b", 0.0) == "", "another player has their own window")
	var open := GSCommandSanity.new()
	_check(open.check_move(Vector3.ZERO, Vector3(1e9, 0, 0), 0.001) == "", "limits of 0 leave a check off")
	_check(open.check_move(Vector3.ZERO, Vector3(NAN, 0, 0), 1.0) == GSCommandSanity.MALFORMED, "but NaN is still refused")
	var off := GSSuspicionConfig.new()
	off.enabled = false
	_check(GSCommandSanity.new(off).check_move(Vector3.ZERO, Vector3(NAN, 0, 0), 1.0) == "", "disabled passes everything")
	_sections += 1


func _watch() -> void:
	var w := GSSuspicionWatch.new()
	add_child(w)
	var det := FakeDetector.new()
	_check(w.attach(det).ok, "a source with a detected signal attaches")
	var bare := Node.new()
	_check(not w.attach(bare).ok, "a source without one fails loudly")
	bare.free()
	_seen.clear()
	w.escalated.connect(func(id, level, score): _seen.append([id, level, score]))
	var sess := FakeSession.new()
	det.detected.emit(sess, &"cheat.speed", false, {})
	_check(_seen.is_empty(), "one suspicion does not escalate")
	det.detected.emit(sess, &"cheat.teleport", true, {})
	_check(_seen.size() == 1 and _seen[0][0] == "p7" and _seen[0][1] == GSSuspicion.Level.KICK, "proof escalates the session by its player id")
	det.detected.emit(sess, &"cheat.teleport", true, {})
	_check(_seen.size() == 1, "staying at the same level does not repeat it")
	_check(GSSuspicionWatch.id_of(42) == "42", "a plain id is its string")
	_check(w.report("q", &"x", true).ok, "game code can report directly")
	_sections += 1


func _layers() -> void:
	var r := GSSuspicionConfig.from_files()
	_check(r.ok and (r.value as GSSuspicionConfig).validate().ok, "the layered config loads and validates", str(r.code()))
	_check(GSSuspicionConfig.new().describe().contains("warn"), "describe names the levels")
	_sections += 1


func _review() -> void:
	var c := GSSuspicionConfig.new()
	c.history_per_player = 2
	c.decay_per_second = 0.0
	var s := GSSuspicion.new(c)
	s.observe("p1", &"cheat.speed", false, 1.0)
	s.observe("p1", &"cheat.aim", true, 2.0)
	s.observe("p1", &"cheat.speed", false, 3.0)
	var h := s.history("p1")
	_check(h.size() == 2 and h[0]["kind"] == "cheat.aim" and h[0]["impossible"] and h[1]["at"] == 3.0, "history keeps the newest detections, oldest first")
	_check(s.history("nobody").is_empty(), "no history for an unknown player")
	var snap := s.to_dict()
	var s2 := GSSuspicion.new(c)
	_check(s2.load_dict(snap).value == 0 and is_equal_approx(s2.score("p1", 3.0), s.score("p1", 3.0)), "to_dict and load_dict round-trip")
	_check(s2.load_dict({"x": 5, "p2": {"score": 1.0, "at": 0.0, "level": 0, "events": 1, "recent": []}}).value == 1 and s2.size() == 1, "load_dict skips bad entries and counts them")
	snap["p1"]["events"] = 99
	_check(s.events("p1") == 3, "to_dict is a copy")
	s.reset("p1")
	_check(s.score("p1", 3.0) == 0.0 and s.level("p1", 3.0) == GSSuspicion.Level.NONE and s.history("p1").is_empty() and s.events("p1") == 3, "reset clears score and history, keeps the count")
	c.history_per_player = 0
	for i in 100:
		s.observe("p3", &"k", false, float(i))
	_check(s.history("p3").size() == 100, "history 0 is unlimited")
	c.history_per_player = -1
	_check(not c.validate().ok, "a negative limit is refused")
	_sections += 1


func _check(ok: bool, what: String, extra: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    ", what)
	else:
		_failed += 1
		print("  FAIL  ", what, "  ", extra)
