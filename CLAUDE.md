# GameSpice Anticheat

Per-player suspicion scoring and command sanity checks for dedicated servers. Read the family [CLAUDE.md](../../CLAUDE.md) first. **The distributable is `addons/dot_anticheat/`**; it requires [GameSpice Core](../dot-core) only (`ln -s ../../dot-core/addons/dot_core addons/dot_core`, gitignored).

| Path | What |
| --- | --- |
| `core/dot_suspicion_config.gd` | `DotSuspicionConfig`: every tunable, `from_files()`, `validate()` |
| `core/dot_suspicion.gd` | `DotSuspicion`: decaying score per player, levels none/warn/kick/ban |
| `core/dot_command_sanity.gd` | `DotCommandSanity`: pure move, look, range and command-rate checks |
| `runtime/dot_suspicion_watch.gd` | `DotSuspicionWatch`: node that listens to a `detected` signal and emits `escalated` |
| `examples/anticheat_selftest.tscn` | the suite |

## Boundary (what it is not)

- **dot-server-security already ships `DotAntiCheat`, `DotAntiCheatConfig`, `DotAntiCheatEvent`** (speed, teleport, aim-snap and more detectors, `detected` signal, escalation through `DotSecurityManager`). Do **not** re-implement detectors here. This addon consumes their detections duck-typed (`kind`, `impossible`) and scores them.
- Our classes are `DotSuspicion*` and `DotCommandSanity` on purpose: `DotAnticheatConfig` would collide with `DotAntiCheatConfig` case-insensitively. Do not rename them to match the addon.
- **dot-moderation** owns punishments, bans and appeals. This addon only reports a level; it never kicks or bans.
- **dot-log** and **dot-telemetry** own logging and analytics; scores may be logged by the game, not here.
- Nothing client-side: no driver, no scanner, nothing is trusted from the client.

## Rules

- Never act: the score emits a level and the game decides. `ban_at` defaults to 0 (never).
- No hard caps: `max_players`, limits and thresholds are config, 0 is unlimited or unchecked, and evictions are counted (`evicted`), never silent.
- Bad config and bad ids fail with a reason (`DotResult`). NaN and infinity from a client are findings, never crashes.
- Time is passed in (`now` seconds) so a test is repeatable; `-1` means the engine clock.
- No autoloads, no scene paths. Scripts keep `class_name` like the sibling addons, but nothing may be loaded by `uid://`.
- **Validate**: `--import`, parse every `.gd`, run the suite through `hv` (see the hv-routing skill).
