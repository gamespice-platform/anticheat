class_name GSSuspicionWatch
extends Node

## Listens to a detector's `detected(session, kind, impossible, detail)` signal (GameSpice Server Security's GSAntiCheat has exactly that), feeds a [GSSuspicion], and emits [signal escalated] when a player reaches a higher level. It does not kick or ban: connect [signal escalated] to whatever does, for example a GSSecurityManager report.

## A player reached a higher level than before.
signal escalated(player_id: String, level: int, score: float)

@export var config: GSSuspicionConfig = null

var suspicion: GSSuspicion
var sanity: GSCommandSanity


func _ready() -> void:
	if config == null:
		config = GSSuspicionConfig.new()
	suspicion = GSSuspicion.new(config)
	sanity = GSCommandSanity.new(config)


## Connects to [param source]'s `detected` signal. Fails loudly when it has none.
func attach(source: Object) -> GSResult:
	if source == null or not source.has_signal("detected"):
		return GSResult.fail(GSError.CODE_INVALID, "suspicion watch needs a source with a detected signal")
	if suspicion == null:
		_ready()
	source.connect("detected", _on_detected)
	return GSResult.success(true)


## Scores one finding directly, for a check run in game code.
func report(player_id: Variant, kind: StringName, impossible: bool = false) -> GSResult:
	var before := suspicion.level(player_id)
	var r := suspicion.observe(player_id, kind, impossible)
	if r.ok and int((r.value as Dictionary)["level"]) > before:
		escalated.emit(str(player_id), int((r.value as Dictionary)["level"]), float((r.value as Dictionary)["score"]))
	return r


func _on_detected(session: Variant, kind: StringName, impossible: bool, _detail: Variant = null) -> void:
	report(id_of(session), kind, impossible)


## A stable id for a session-like object: its player_id, session_id or id, else its string form.
static func id_of(session: Variant) -> String:
	if session is Object:
		for key in ["player_id", "session_id", "id"]:
			var v: Variant = (session as Object).get(key)
			if v != null:
				return str(v)
	return str(session)
