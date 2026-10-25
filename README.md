# Deathly Echo

A wave-based first-person zombie shooter (project name: **Zombie FPS**) built with **Godot 4.7**, inspired by *Deathly Stillness*.

Everything you see and hear is generated at runtime: geometry is primitive meshes assembled in code, and **all audio is synthesised** — the project ships with zero external art or sound assets.

**Status: v0.9.0** — feature-complete for a public test build. Single-player, Windows.

---

## Quick Start

**Prerequisites:** Godot 4.7.x stable (Windows x64). No assets to download.

```bash
# Editor: Import → project.godot → F5
# Command line:
Godot_v4.7.1-stable_win64.exe --path ./
```

### Building a shareable .exe

An export preset is included (`export_presets.cfg`, embedded PCK → single file):

1. `Editor → Manage Export Templates → Download and Install` (must match your editor version)
2. `Project → Export → Windows Desktop`
3. Export → `build/ZombieFPS.exe`
4. Send that one file; no `.pck` needed

---

## Controls

| Key | Action |
|---|---|
| W / A / S / D | Move |
| Mouse | Look |
| Left Click | Shoot |
| Right Click | Scope (sniper only: FOV 75 → 22, sensitivity ×0.35) |
| R | Reload · Restart (when dead) |
| G | Grenade (starts with 3) |
| F | Class skill |
| 1 / 2 / 3 | Switch weapon |
| Space | Jump |
| Shift | Sprint (×1.8) |
| Esc | Pause / Return to menu (when dead) |
| B | Debug: jump to the next BOSS wave |
| F3 | Debug overlay: FPS · wave · enemies · draw calls · objects · VRAM |
| Click screen | Re-lock mouse |

**Pause panel:** `↑` `↓` select a row, `←` `→` adjust — master volume, mouse sensitivity, crosshair colour (white / green / red). All persist to disk.

**Main menu:** `←` `→` or `A` / `D` to pick a class, `Enter` / `Space` or click a card to start. `U` opens the blood-crystal shop (`1` / `2` to buy, `Esc` back).

---

## Classes

| Class | Loadout | Starting weapon | Skill (CD) |
|---|---|---|---|
| Assault | Pistol / SMG / Shotgun | SMG | Overdrive — fire rate ×2 for 4 s (18 s) |
| Hunter | Pistol / Sniper / SMG | Sniper | Death Mark — 2.5× damage on the marked zombie for 5 s (20 s) |
| Heavy | Pistol / Shotgun / Grenade Launcher | Shotgun | Shockwave — stun zombies within 8 m for 3 s (16 s) |

## Weapons

| Weapon | Damage | Mag | Reserve | Interval | Spread | Pellets | Auto |
|---|---:|---:|---:|---:|---:|---:|---|
| Pistol | 60 | 12 | 48 | 0.32 s | 0.02 | 1 | no |
| SMG | 25 | 32 | 120 | 0.10 s | 0.07 | 1 | yes |
| Shotgun | 15 | 6 | 36 | 0.75 s | 0.18 | 6 | no |
| Sniper | 200 | 5 | 25 | 1.20 s | 0.001 | 1 | no |
| Grenade Launcher | 150 (direct) | 3 | 12 | 0.80 s | 0.01 | 1 | no |

Hit detection is raycast-based with real occlusion; each pellet rolls its own spread. The launcher fires a real projectile (`grenade.tscn`) at 35 m/s: 150 direct damage on impact plus the explosion's 100→20 falloff.

## Enemies

| Type | Speed | HP | Contact damage | Behaviour |
|---|---:|---:|---:|---|
| Normal | 2.0 | 60 | 10 | Melee chase |
| Runner | 4.0 | 30 | 8 | Fast chase |
| Exploder | 2.5 | 40 | 50 | Detonates within 3.5 m |
| Tank | 1.2 | 200 | 25 | Slow, ×1.3 scale |
| Charger | 2.5 → 6.5 | 55 | 0 | Sprints from 10 m; impact blast 80→20 over 4 m |
| Spitter | 2.2 | 45 | 0 | Holds 8–15 m, 1.2 s wind-up, lobs acid (3 m radius, 15 dmg) |
| BOSS | 1.8 | 800 | 35 | ×1.8 scale, three phases (below) |

**Elites** — from wave 4, 20% of spawns get ×2 HP, ×1.2 scale and one affix:

| Affix | Effect |
|---|---|
| Frenzy | +40% speed, blood-red body |
| Split | Spawns 2 normal zombies on death, purple body |
| Lifesteal | Heals 20 HP per hit on the player, green body |

Elites always drop a medkit or ammo box **and** a blood crystal.

## BOSS

Every 5th wave. Three phases driven by HP:

1. **> 50%** — charge / summon 2 runners / roar (slows the player for 3 s)
2. **50–25%** — +20% speed, summon replaced by an eight-projectile acid ring
3. **< 25%** — roots in place, paints a red circle under the player every 3 s (1 s fuse, 30 damage)

From wave 11 onward each BOSS wave spawns **two** bosses: a *charger* variant (×1.7 speed, ×0.85 HP, rams non-stop) and a *spitter* variant (holds 9–16 m, lobs acid + acid rings every 8 s). Both get their own HP bar.

## Waves & Endless

- Spawn count: `round((4 + wave × 2) × count_mult)`, placed in a ring 8–15 m around the player
- **Wave 3 "Swarm"** — count ×2.5, HP ×0.8 · **Wave 9 "Frenzy"** — speed ×1.4, damage ×1.5
- Clearing a wave opens a portal that rotates to one of **8 procedurally generated maps**
- Wave 10 is not an ending: the run continues into **endless**, scaling HP and damage by **1.10^(wave − 10)**

## Between-Wave Upgrades

Pick 1 of 3 random cards after each cleared wave. **15 cards**, all stackable:

| Category | Card | Effect |
|---|---|---|
| Core | Piercing Core | +20% weapon damage |
| Core | Rapid Cycling | +15% fire rate |
| Core | Tactical Reload | +30% reload speed |
| Core | Lightfoot | +12% move speed |
| Core | Tough Body | +25 max HP, heal to full |
| Core | Ammo Backpack | +40% reserve ammo |
| Core | Grenade Supply | +2 grenades |
| Capacity | Extended Mag | +50% magazine size |
| Capacity | Launcher Drum | +2 launcher rounds |
| Trade-off | Overclock | +25% fire rate, −10% damage |
| Survival | Composite Armor | −15% damage taken |
| Survival | Field Medic | Heal 8 HP per kill |
| Combat | Chain Detonation | Kills explode for 35 damage in a 3 m radius |
| Combat | Stabilised Barrel | −40% spread |
| Growth | Crystal Resonance | Blood-crystal drop rate doubled |

## Meta Progression (Blood Crystals)

Blood crystals drop from 12% of normal kills (and always from elites). They are banked **when you die**, then spent in the main-menu shop:

| Upgrade | Effect | Cost | Max |
|---|---|---|---|
| Piercing Core | +10% base weapon damage per level | 8 + 6 × level | 5 |
| Tough Body | +20 starting HP per level | 10 + 8 × level | 5 |

## Hazards

| Object | Behaviour |
|---|---|
| Explosive barrel | 35 HP; 120 damage in 4 m; chain-detonates nearby barrels after 0.2 s |
| Spike trap | 15 damage when stepped on, then a 3 s cooldown (spikes glow red) |
| Gas canister | 30 HP; explodes into a 5 s toxic cloud (3.5 m, 10 damage/s to zombies) |

Barrels show a "可引爆" label and spike traps show "危险" when the player comes within 3 m.

## Presentation

- Self-drawn crosshair (dot + four ticks, kicks out on fire, colour selectable), hit marker, damage-driven vignette, camera shake, 0.03 s hit-stop on heavy hits or kills
- **Audio, all synthesised in `audio_manager.gd`**: gunshot, hit thud, explosion (72→26 Hz sweep + noise, distance-attenuated), footsteps, zombie growls (throttled to one per 0.55 s), pickup chime, and a seamless 4 s 55 / 55.5 Hz drone on its own low-passed BGM bus at −15 dB
- Death screen shows wave, survival time, kills, damage dealt, crystals earned, favourite upgrade and your all-time bests — with a `[NEW RECORD]` tag when you beat one

## Save Data

`user://zombie_save.json` (on Windows: `%APPDATA%\Godot\app_userdata\Zombie FPS\`)

Stores crystals, both permanent upgrade levels, volume, sensitivity, crosshair colour, and personal bests (wave / kills / survival time). The file carries a `version` field for future migrations and is backed up to `zombie_save.bak.json` before every write; a corrupted main file falls back to the backup.

---

## Performance Notes

Target hardware is a low-end laptop (MX550 4 GB). Measures already in place:

| Area | Measure |
|---|---|
| Rendering | MSAA 2x, 3D render scale 0.85 (UI stays native) |
| Enemies | Object pool — no instantiate/free during play; dead bodies drop their collision layers and leave the `zombie` group immediately |
| Materials | Shared cache keyed by colour / roughness / emission; swapped rather than mutated |
| Lights | No per-zombie dynamic lights (self-illumination only); blast flashes are short-lived and bind their tween to themselves |
| Recoil / shake | `move_toward` instead of tweens |
| UI | Cached HUD node, 0.25 s debug refresh, redraw only when a value changes |
| Audio | 10-voice SFX pool, growl throttling |

Known cost: each zombie is assembled from 12 meshes, so a 15-zombie swarm is roughly 180 draw calls. Merging the body into a single `ArrayMesh` is the next planned optimisation.

---

## Project Structure

```
ZombieFPS/
├── project.godot            # Autoloads: GameState / ObjectPool / AudioManager
├── export_presets.cfg       # Windows Desktop, embedded PCK
├── scenes/
│   ├── menu.tscn            # Class select + crystal shop (all drawn in _draw)
│   ├── main.tscn            # World root
│   ├── player.tscn          # Player + Head/Camera3D/Gun/Muzzle, ShootTimer, ReloadTimer
│   ├── zombie.tscn          # Zombie base (body assembled at runtime), AttackTimer
│   ├── hud.tscn             # HUD overlay
│   └── grenade.tscn         # Grenade / launcher round / acid projectile
└── scripts/
    ├── game_state.gd        # Autoload: run state, save file, settings, records, hit-stop
    ├── object_pool.gd       # Autoload: zombie pool
    ├── audio_manager.gd     # Autoload: SFX pool + all synthesis + drone BGM
    ├── player.gd            # Input, movement, weapons, recoil, skills, upgrades
    ├── zombie.gd            # AI, body assembly, elite affixes, BOSS phases, variants, drops
    ├── wave_manager.gd      # Waves, map generation, hazards, portal, card draw
    ├── hud.gd               # HUD, crosshair, vignette, pause/upgrade/gameover panels, boss bars
    ├── menu.gd              # Class select + crystal shop
    ├── minimap.gd           # Minimap drawing
    ├── barrel.gd            # Explosive barrel (+ chain)
    ├── spike_trap.gd        # Spike trap
    ├── gas_tank.gd          # Gas canister
    ├── gas_cloud.gd         # Toxic cloud
    └── grenade.gd           # Projectile physics + explosion
```

---

## Development Notes

Built as a learning project with an AI-assisted workflow. The lessons that cost the most time:

1. **A tween bound to a dying node dies with it.** Explosion code created a flash, tweened it on `self`, then freed `self` in the same frame — the fade never ran and every blast leaked a permanent light. Bind the tween to the node that survives (the flash), not the caster.
2. **Group membership order matters.** `get_first_node_in_group("hud")` cached in the player's `_ready` returned `null`, because the HUD only joined the group in *its* `_ready`. Scene-declared `groups=[...]` register before any `_ready`; lazy lookup is the safe default.
3. **Pooled objects carry their previous life.** A recycled boss kept its variant, scale and colours until every new field was reset in `reset_for_spawn()`. Anything added later must be reset there too.
4. **Chained explosions need `call_deferred`.** Kill-triggered explosions that damage other zombies would otherwise recurse synchronously, nesting dozens of frames deep in one tick.
5. **`add_child()` before `global_position`.** Outside the tree the global transform is identity, so the assignment silently does nothing.
6. **Saves need a version and a backup.** A half-written JSON is unrecoverable; writing a `.bak` first and falling back on parse failure costs ten lines.

---

## Known Issues / Roadmap

- All visuals are primitive boxes — no animated or skeletal character models
- Zombies path straight at the player; no navmesh, so they can catch on corners in wall-heavy maps
- UI strings are hard-coded Chinese — no localisation layer yet
- Dual-boss waves get one HP bar each, but the "BOSS" label follows the primary one
- No automated tests or CI
- Single-player only; no multiplayer, no Steam integration

Weapon stats are now data-driven — each gun is a `WeaponData` resource in `resources/weapons/*.tres`, with the old table kept as a fallback so a missing or malformed `.tres` degrades to the built-in values instead of breaking the game. Upgrades and enemies are still in code (phase B3/B4).

Planned: upgrade / enemy definitions as resources, enemy state machine, zombie mesh merging, navmesh baking.

The phased engineering plan lives in [`docs/updates/`](docs/updates/) — phase A (shipping) is done; B is in progress; C–E cover HUD split, enemy state machine and rendering/localisation/tests.

---

## Credits

- Engine: Godot 4.7
- Inspired by *Deathly Stillness* (Steam, free)
- Built with an AI-assisted workflow
