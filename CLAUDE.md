# GameSpice Anticheat

Per-player suspicion scoring and command sanity checks for dedicated servers. Read the family [CLAUDE.md](../../CLAUDE.md) first. **The distributable is `addons/gs_anticheat/`**; it requires [GameSpice Core](../gs-core) only (`ln -s ../../gs-core/addons/gs_core addons/gs_core`, gitignored).

| Path | What |
| --- | --- |
| `core/gs_suspicion_config.gd` | `GSSuspicionConfig`: every tunable, `from_files()`, `validate()` |
| `core/gs_suspicion.gd` | `GSSuspicion`: decaying score per player, levels none/warn/kick/ban |
| `core/gs_command_sanity.gd` | `GSCommandSanity`: pure move, look, range and command-rate checks |
| `runtime/gs_suspicion_watch.gd` | `GSSuspicionWatch`: node that listens to a `detected` signal and emits `escalated` |
| `examples/anticheat_selftest.tscn` | the suite |

## Boundary (what it is not)

- **gs-server-security already ships `GSAntiCheat`, `GSAntiCheatConfig`, `GSAntiCheatEvent`** (speed, teleport, aim-snap and more detectors, `detected` signal, escalation through `GSSecurityManager`). Do **not** re-implement detectors here. This addon consumes their detections duck-typed (`kind`, `impossible`) and scores them.
- Our classes are `GSSuspicion*` and `GSCommandSanity` on purpose: `GSAnticheatConfig` would collide with `GSAntiCheatConfig` case-insensitively. Do not rename them to match the addon.
- **gs-moderation** owns punishments, bans and appeals. This addon only reports a level; it never kicks or bans.
- **gs-log** and **gs-telemetry** own logging and analytics; scores may be logged by the game, not here.
- Nothing client-side: no driver, no scanner, nothing is trusted from the client.

## Rules

- Never act: the score emits a level and the game decides. `ban_at` defaults to 0 (never).
- No hard caps: `max_players`, limits and thresholds are config, 0 is unlimited or unchecked, and evictions are counted (`evicted`), never silent.
- Bad config and bad ids fail with a reason (`GSResult`). NaN and infinity from a client are findings, never crashes.
- Time is passed in (`now` seconds) so a test is repeatable; `-1` means the engine clock.
- No autoloads, no scene paths. Scripts keep `class_name` like the sibling addons, but nothing may be loaded by `uid://`.
- **Validate**: `--import`, parse every `.gd`, run the suite through `hv` (see the hv-routing skill).
