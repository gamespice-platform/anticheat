class_name GSSuspicionConfig
extends GSConfig

## Every tunable of the suspicion score and the command sanity checks. Layers, weakest first: these defaults, `cfg/addon/gs_anticheat/*.yml`, the game's files, the operator's files, `GS_ANTICHEAT_*` environment variables, then `--anticheat-*` flags. A limit of 0 is "unchecked" or "unlimited"; nothing here is a hidden cap.

const ADDON := "gs-anticheat"

## Master switch. Off, nothing is scored and every sanity check passes.
@export var enabled: bool = true

@export_group("Score")
## Points added by a detection whose kind has no entry in `weights`.
@export_range(0.0, 1000.0, 0.1) var default_weight: float = 1.0
## Points added by a detection that is proof (the server re-simulated it) rather than suspicion.
@export_range(0.0, 100000.0, 1.0) var impossible_weight: float = 100.0
## Points forgiven per second; 0 means the score never decays.
@export_range(0.0, 1000.0, 0.1) var decay_per_second: float = 0.5
## Per-kind points as "kind=weight", for example "cheat.aim_snap=8".
@export var weights: PackedStringArray = PackedStringArray()
## Players tracked at once; 0 is unlimited. At the limit the lowest score is forgotten first and counted.
@export_range(0, 1000000, 1) var max_players: int = 0

## Recent detections kept per player for a person to read; 0 is unlimited.
@export_range(0, 100000, 1) var history_per_player: int = 20

@export_group("Escalation")
## Score at which a player is flagged for a human to look at; 0 turns the level off.
@export_range(0.0, 100000.0, 1.0) var warn_at: float = 20.0
## Score at which the game should remove the player from the match; 0 turns the level off.
@export_range(0.0, 100000.0, 1.0) var kick_at: float = 60.0
## Score at which the game should ban; 0 means never, which is the safe default.
@export_range(0.0, 100000.0, 1.0) var ban_at: float = 0.0

@export_group("Command sanity")
## Fastest legal movement, in units per second; 0 leaves it unchecked.
@export_range(0.0, 100000.0, 1.0) var max_speed: float = 0.0
## Fastest legal turn, in degrees per second; 0 leaves it unchecked.
@export_range(0.0, 100000.0, 1.0) var max_turn_rate: float = 0.0
## Most commands one player may send per second; 0 leaves it unchecked.
@export_range(0.0, 100000.0, 1.0) var max_command_rate: float = 0.0
## Largest legal distance from the origin on any axis; 0 leaves it unchecked.
@export_range(0.0, 10000000.0, 1.0) var world_extent: float = 0.0


func env_prefix() -> String:
	return "GS_ANTICHEAT_"


func cli_prefix() -> String:
	return "--anticheat-"


func validate() -> GSResult:
	if kick_at > 0.0 and warn_at > kick_at:
		return GSResult.fail(GSError.CODE_INVALID, "anticheat warn_at %s is above kick_at %s" % [warn_at, kick_at])
	if ban_at > 0.0 and kick_at > ban_at:
		return GSResult.fail(GSError.CODE_INVALID, "anticheat kick_at %s is above ban_at %s" % [kick_at, ban_at])
	if history_per_player < 0 or max_players < 0:
		return GSResult.fail(GSError.CODE_INVALID, "anticheat limits cannot be negative (0 is unlimited)")
	for entry in weights:
		if not "=" in entry or not str(entry.get_slice("=", 1)).is_valid_float():
			return GSResult.fail(GSError.CODE_INVALID, "anticheat weight '%s' is not kind=number" % entry)
	return GSResult.success(self)


## The weights table as a dictionary of kind to points.
func weight_table() -> Dictionary:
	var out := {}
	for entry in weights:
		if "=" in entry:
			out[entry.get_slice("=", 0).strip_edges()] = float(entry.get_slice("=", 1))
	return out


## Defaults, then `cfg/addon/gs_anticheat/*.yml` and the game tier, then environment and command line.
static func from_files() -> GSResult:
	var cfg := GSSuspicionConfig.new()
	var files := GSAddonConfig.load_dir(ADDON)
	if not files.ok:
		return files
	cfg.apply_dictionary(files.value as Dictionary, "yml")
	return cfg.load_layered()


func describe() -> String:
	return "anticheat %s warn %s kick %s ban %s decay %s/s" % [
		"on" if enabled else "off", warn_at, kick_at, ban_at, decay_per_second]
