# Deathly Echo

A first-person zombie wave survival game built with Godot 4.7.1, inspired by *Deathly Stillness*.

Built as a learning project with AI-assisted development workflow.

---

## Quick Start

### Prerequisites
- Godot 4.7.1 stable (Windows x64)
- No external assets required — all visuals are primitive meshes, all audio is procedurally generated

### Run
1. Open Godot Engine → Import → select `project.godot`
2. Press F5 (play) or run from command line:
```bash
Godot_v4.7.1-stable_win64.exe --path ./
```

---

## Controls

| Key | Action |
|---|---|
| W / A / S / D | Move |
| Mouse | Look around |
| Left Click | Shoot |
| Right Click | Scope (sniper only) |
| R | Reload / Restart (when dead) |
| G | Grenade (3 per life) |
| F | Class skill (cooldown) |
| 1 / 2 / 3 | Switch weapon |
| Space | Jump |
| Shift | Sprint (×1.8) |
| Esc | Toggle pause (dedicated pause panel) / Return to menu when dead |
| B | Debug: jump straight to the next BOSS wave |
| F3 | Debug overlay: FPS / wave / enemy count / draw calls / objects / VRAM |
| Click screen | Re-lock mouse |

**Pause panel settings**: `↑` `↓` to select a row, `←` `→` to adjust — master volume, mouse sensitivity, crosshair colour (white / green / red). All persist to disk.

**Menu**: `←` `→` or `A` / `D` to select a class, `Enter` / `Space` or click a card to start. `U` (or the button) opens the blood-crystal shop: `1` / `2` to buy a permanent upgrade, `Esc` to go back.

---

## Classes & Weapons

| Class | Weapons | Starting Weapon | Skill |
|---|---|---|---|
| **Assault** | Pistol / SMG / Shotgun | SMG | Fire rate ×2 for 4s (18s CD) |
| **Hunter** | Pistol / Sniper / SMG | Sniper | Death Mark: ×2.5 damage on marked zombie for 5s (20s CD) |
| **Heavy** | Pistol / Shotgun / Grenade Launcher | Shotgun | Shockwave: stun zombies within 8m for 3s (16s CD) |

### Weapon Stats

| Weapon | Damage | Mag | Reserve | Fire Rate | Spread | Pellets | Auto |
|---|---|---|---|---|---|---|---|
| Pistol | 60 | 12 | 48 | 0.32s | 0.02 | 1 | No |
| SMG | 25 | 32 | 120 | 0.10s | 0.07 | 1 | Yes |
| Shotgun | 15 | 6 | 36 | 0.75s | 0.18 | 6 | No |
| Sniper | 200 | 5 | 25 | 1.20s | 0.001 | 1 | No |
| Grenade Launcher | 150 + AoE | 3 | 12 | 0.80s | — | 1 | No |

- Gun models are procedurally assembled from `BoxMesh` — the sniper has a scope and bipod, the grenade launcher a stubby barrel and drum magazine.
- Hit detection is raycast-based with real occlusion; multi-pellet weapons roll spread per pellet.
- The grenade launcher **does not use a raycast**. It spawns a physical projectile at 35 m/s with a flat trajectory; on impact with a zombie it deals 150 direct damage, then detonates for area damage. It reuses `grenade.tscn` with continuous collision detection enabled to avoid tunnelling through thin walls.

---

## Features Implemented

### Core Gameplay
- First-person mouse look + WASD movement + jump + sprint
- 3 selectable classes with distinct skill loadouts
- 5 weapons with procedural models, reload, per-weapon spread
- Grenades: 2.5s fuse, detonates on contact with zombies or static geometry, 5m radius, damage 100→20 falloff
- Skill system with per-class cooldowns
- 10-wave progression, then **endless mode** (no victory screen). BOSS every 5 waves.
- Endless scaling: HP and damage grow at **1.10^(w-10)** from wave 11 (wave 20 ≈ ×2.6).
- Endless BOSS waves spawn a **dual boss**: a charger (fast, ×1.7 speed / ×0.85 HP) and a spitter (keeps 9–16 m, throws acid + acid rings every 8 s).
- 8 hand-tuned maps with unique palettes, rotated through a portal between waves
- Pause system (Esc) with a dedicated panel showing this run's upgrades and stat multipliers
- Between-wave upgrade system: pick 1 of 3 from a **15-card pool** (stackable), including the glass-cannon "overclock" card (rate +25%, damage −10%)
- Sniper scope: right click to zoom (FOV 75 → 22), sensitivity scaled to 35%, gun model hidden

### Enemy Types

| Type | Speed | HP | Damage | Behavior |
|---|---|---|---|---|
| Normal | 2.0 | 60 | 10 | Melee chase |
| Runner | 4.0 | 30 | 8 | Fast chase |
| Exploder | 2.5 | 40 | 50 | Proximity self-destruct, r=3.5m |
| Tank | 1.2 | 200 | 25 | Slow, high HP, ×1.3 scale |
| Charger | 2.5 → 6.5 | 55 | — | 10m trigger → sprint → impact blast, r=4m hard radius, 80→20 falloff |
| BOSS | 1.8 | 800 | 35 | Charge / summon 2 runners / roar (player slow 3s), ×1.8 scale |

- Zombie bodies are procedurally assembled from `BoxMesh` (pelvis / torso / shoulders / arms / legs / head / hair / eyes), with a 40% chance female variant.
- Walk animation: alternating leg swing, arms reaching forward, torso lean, head slightly down.

### Wave Modifiers
- **Wave 3** "Swarm": spawn count ×2.5, HP ×0.8
- **Wave 9** "Frenzy": enemy speed ×1.4, damage ×1.5

### Drops
30% chance on zombie death:

| Drop | Effect |
|---|---|
| Ammo box | Reserve +30 |
| Medkit | HP +40 |
| Speed serum | 20s speed ×1.5 |
| Grenade | Grenades +1 |
| **Blood crystal** | +1 meta currency (12% on normal kills, guaranteed on elites) |

### Meta Progression (Blood Crystals)
- Crystals are banked per run and **settled on death** (`GameState.settle_run()`, guarded by `run_settled` so it can never double-count).
- Save file: `user://zombie_save.json` — crystals, both permanent upgrade levels, volume, sensitivity, crosshair colour.
- Shop in the main menu (`U`): **Piercing Core** (+10% base damage per level) and **Tough Body** (+20 starting HP per level), 5 levels each, cost `base + step × level`.

### Hazards (2 per map, randomly chosen)
| Hazard | Behaviour |
|---|---|
| Spike trap | 15 damage when stepped on, then 3s cooldown (spikes glow red while cooling) |
| Gas canister | 30 HP, shoots explode into a 5s toxic cloud; zombies inside take 10 damage per second |

### Visual & Audio
- Enemy self-illumination distinguishes types (no per-zombie dynamic lights)
- Hit marker: `+` turns into a red `X` for 0.15s
- Recoil: gun kicks to `z = -0.55` and view pitches +1.5°, both eased back with `move_toward` (no tweens)
- **All audio is synthesised at runtime, zero asset files** (`audio_manager.gd`):
  - gunshot (125 ms noise), hit thud, explosion (72→26 Hz sweep + white noise, 0.6 s decay, distance-attenuated)
  - footsteps (35 ms low noise, 0.42 s cadence / 0.30 s while sprinting)
  - zombie growls (58→44 Hz saw + vibrato, 4–8 s per zombie, globally throttled to one per 0.55 s)
  - pickup chime (880 → 1320 Hz), plus a 4 s seamless 55 / 55.5 Hz drone BGM on its own low-passed bus at −15 dB
- Blood particles on zombie hit, wall decals on surface hit (fade after 2s)
- Interactable hints: barrels show "可引爆" and spike traps show "危险" via billboarded Label3D within 3 m
- Minimap: player dot + facing line, ±40m range, red enemy blips, orange BOSS

---

## Project Structure

```
Deathly-Echo/
├── project.godot          # Project config, main scene = menu.tscn
├── scenes/
│   ├── menu.tscn          # Character select + blood-crystal shop (all via _draw)
│   ├── main.tscn          # Game world root
│   ├── player.tscn        # Player + Head/Camera3D/Gun/Muzzle, ShootTimer, ReloadTimer
│   ├── zombie.tscn        # Zombie base (body assembled at runtime), AttackTimer
│   ├── hud.tscn           # HUD overlay (health/ammo/wave/minimap/BOSS bar)
│   └── grenade.tscn       # Grenade RigidBody3D (grenade / launcher / acid share it)
└── scripts/
    ├── game_state.gd      # Autoload: global state, save file, settings, hit-stop
    ├── object_pool.gd     # Autoload: zombie object pool
    ├── audio_manager.gd   # Autoload: 10-voice SFX pool
    ├── menu.gd            # Character select + crystal shop
    ├── player.gd          # Player control, weapons, skills, hit detection, audio synth
    ├── zombie.gd          # Zombie AI, body building, elite affixes, BOSS phases, drops
    ├── wave_manager.gd    # Wave spawning, map generation, hazards, portal
    ├── hud.gd             # HUD, crosshair, vignette, pause/upgrade/game-over panels
    ├── minimap.gd         # Minimap drawing
    ├── barrel.gd          # Explosive barrel (+ chain reaction)
    ├── spike_trap.gd      # Spike trap (15 damage / 3s cooldown)
    ├── gas_tank.gd        # Gas canister (30 HP, explodes into a cloud)
    ├── gas_cloud.gd       # Toxic cloud (5s, 10 dmg/s to zombies)
    └── grenade.gd         # Grenade physics + explosion
```

---

## Performance Notes

The game targets low-end hardware (tested on an MX550 4GB). Key measures:

| Measure | Approach |
|---|---|
| Grenade launcher | Projectile-based (no per-shot raycast); reuses the grenade scene with CCD |
| Zombie materials | `static _mat_cache` keyed by color+roughness+emission; identical parts share one material |
| HUD lookup | `hud_node` cached in `_ready()` instead of per-shot group search |
| Recoil | `move_toward` interpolation instead of `create_tween()` |
| Per-zombie lights | Removed; type recognition is done with material self-emission |

---

## Development Notes (Lessons Learned)

This project was built through a structured AI-assisted workflow. Key takeaways for Godot 4 beginners:

### 1. A Single Parse Error Kills the Whole Script
**Bug**: `var query := PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(...)` — using `:=` (type inference) *and* an explicit type is parsed as "assignment inside an expression", so the script never loads at all.
**Fix**: `var query := PhysicsRayQueryParameters3D.create(...)`
**Lesson**: One bad line anywhere in a file blocks the entire script. If a scene shows nothing at all, check the script errors panel first.

### 2. Shared Materials Mutate Everywhere
**Bug**: Setting `albedo_color` on a material in `zombie.tscn` (a sub_resource) changed the color of *all* zombie instances at once. The same hazard appears with a runtime material cache — `_apply_body_visual()` originally mutated `material_override` in place, which would have repainted every zombie in the wave.
**Fix**: Set `resource_local_to_scene = true` on the material resource, or — for a runtime cache — never mutate a cached material; fetch a different one and swap `material_override` wholesale.
**Lesson**: In Godot 4, resources are shared by default. If you modify a material at runtime and see the effect everywhere, this is why.

### 3. `PROCESS_MODE_ALWAYS` Un-pauses Physics Too
**Bug**: Setting `process_mode = PROCESS_MODE_ALWAYS` on the player so Esc still works during pause also un-paused `_physics_process` — the player could walk and shoot while paused.
**Fix**: Keep the node ALWAYS but add an explicit `if get_tree().paused: return` in `_physics_process` and in `_input`.
**Lesson**: `process_mode` is all-or-nothing per node. There is no "input only" mode.

### 4. Type-Safe Arrays Cause Silent Crashes
**Bug**: `var current_weapons: Array[String] = ["pistol"]` crashed silently when assigned from an untyped dictionary return. Godot 4 stops `_ready()` execution with no obvious error in-game.
**Fix**: Remove the explicit type annotation when the source can return an untyped Array.
**Lesson**: Godot 4 typed arrays are strict — if you see a grey screen after scene load, check script errors first.

### 5. Node Must Be In Tree Before Setting Global Transform
**Bug**: `hole.global_position = pos` before `add_child(hole)` silently failed — a node not inside the tree returns identity from `global_transform`.
**Fix**: Add the child first, then set the position.
**Lesson**: Always call `add_child()` before modifying `global_position` / `global_rotation`.

### 6. Defensive Checks for Swapped-Out Nodes
**Bug**: Flamethrower effects crashed when the old gun barrel was `queue_free`'d during a weapon swap, but a pending frame still referenced it.
**Fix**: `if not is_instance_valid(muzzle): return` before accessing.
**Lesson**: When using `queue_free()` on a node, always guard references in async / deferred code paths.

### 7. Separate Aim From Recoil
**Bug**: Adding recoil directly to `head.rotation.x` while mouse look also writes `head.rotation.x` means the two fight each other — recoil either gets overwritten by the next mouse motion, or accumulates until the view points at the sky.
**Fix**: Split into `head_base_pitch` (mouse only) + `head_recoil_offset` (recoil only), and compose the final rotation each frame.
**Lesson**: Never let two systems write the same transform property.

### 8. Git Version Control Is Non-Negotiable
With multiple AI agents iterating on the same codebase, a single bad edit could break everything. Git commits after each milestone made rollback trivial.

---

## Known Issues / Roadmap

- [ ] All visuals are primitive boxes — no animated character models
- [ ] BOSS abilities implemented but not extensively playtested
- [ ] No background music

---

## Credits

- Engine: Godot 4.7.1
- Inspired by: *Deathly Stillness* (Steam, free)
- Developed with AI-assisted workflow (DeepSeek + Doubao)
