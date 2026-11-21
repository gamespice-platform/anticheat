class_name GSCommandSanity
extends RefCounted

## Pure checks on what a client claims, run on the server. Each returns the detection kind it matched, or an empty string when the claim is possible. They keep no state except the command-rate window, and they trust nothing: a NaN, an infinity or a value out of range is a finding, not a crash. The kinds use the same strings as GameSpice Server Security's detectors so a score can mix both.

const SPEED := "cheat.speed"
const TELEPORT := "cheat.teleport"
const TURN := "cheat.aim_snap"
const RATE := "cheat.timing"
const RANGE := "cheat.out_of_range"
const MALFORMED := "cheat.malformed"

var config: GSSuspicionConfig

var _stamps: Dictionary = {}   # player id -> PackedFloat64Array of recent command times


func _init(p_config: GSSuspicionConfig = null) -> void:
	config = p_config if p_config != null else GSSuspicionConfig.new()


## [param from] to [param to] in [param dt] seconds. A finite step longer than the speed limit allows is SPEED; a non-finite one is MALFORMED.
func check_move(from: Vector3, to: Vector3, dt: float) -> String:
	if not config.enabled:
		return ""
	if not _finite3(from) or not _finite3(to) or not is_finite(dt) or dt < 0.0:
		return MALFORMED
	var out := check_range(to)
	if out != "":
		return out
	if config.max_speed > 0.0:
		var d := from.distance_to(to)
		if dt <= 0.0:
			return SPEED if d > 0.0 else ""
		if d / dt > config.max_speed:
			return SPEED
	return ""


## A position outside the world. With `world_extent` 0 only a non-finite one is refused.
func check_range(pos: Vector3) -> String:
	if not _finite3(pos):
		return MALFORMED
	if config.world_extent > 0.0 and maxf(absf(pos.x), maxf(absf(pos.y), absf(pos.z))) > config.world_extent:
		return RANGE
	return ""


## A view change of [param yaw_delta] and [param pitch_delta] degrees in [param dt] seconds.
func check_look(yaw_delta: float, pitch_delta: float, dt: float) -> String:
	if not config.enabled:
		return ""
	if not is_finite(yaw_delta) or not is_finite(pitch_delta) or not is_finite(dt) or dt < 0.0:
		return MALFORMED
	if config.max_turn_rate > 0.0:
		var turn := sqrt(yaw_delta * yaw_delta + pitch_delta * pitch_delta)
		if dt <= 0.0:
			return TURN if turn > 0.0 else ""
		if turn / dt > config.max_turn_rate:
			return TURN
	return ""


## One command arriving from [param player_id] at [param now] seconds. Counts commands in the last second and answers RATE once the limit is passed.
func check_command(player_id: Variant, now: float) -> String:
	if not config.enabled or config.max_command_rate <= 0.0:
		return ""
	if not is_finite(now):
		return MALFORMED
	var id := str(player_id)
	var stamps: PackedFloat64Array = _stamps.get(id, PackedFloat64Array())
	var kept := PackedFloat64Array()
	for s in stamps:
		if now - s < 1.0:
			kept.append(s)
	kept.append(now)
	_stamps[id] = kept
	return RATE if float(kept.size()) > config.max_command_rate else ""


func forget(player_id: Variant) -> void:
	_stamps.erase(str(player_id))


static func _finite3(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)
