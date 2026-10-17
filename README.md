[README.md](https://github.com/user-attachments/files/33596103/README.md)
# Zombie FPS

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
| R | Reload |
| G | Grenade (3 per life) |
| F | Class skill (cooldown) |
| 1 / 2 / 3 | Switch weapon |
| Space | Jump |
| Shift | Sprint |
| Esc | Release mouse |
| Click screen | Re-lock mouse |

---

## Classes & Weapons

| Class | Weapons | Starting Weapon | Skill |
|---|---|---|---|
| **Assault** | Pistol / SMG / Shotgun | SMG | Fire rate ×2 |
| **Hunter** | Pistol / Sniper / SMG | Sniper | Death Mark (×2.5 damage on marked zombie) |
| **Heavy** | Pistol / Shotgun / Flamethrower | Shotgun | Stun grenade (AoE slow) |

---

## Features Implemented

### Core Gameplay
- First-person mouse look + WASD movement + jump + sprint
- 3 selectable classes with distinct skill loadouts
- 5 weapons: pistol, SMG, shotgun, sniper, flamethrower
- Reload system, grenade system, skill system with cooldown
- Raycast-based hit detection with occlusion check
- 10-wave progression system
- BOSS fight on wave 5 and wave 10
- 8 procedurally generated maps

### Enemy Types
| Type | Speed | HP | Behavior | Visual |
|---|---|---|---|---|
| Normal | 2.0 | 60 | Melee chase | Dark red |
| Runner | 4.0 | 30 | Fast chase | Dark red |
| Exploder | 2.5 | 40 | Proximity explosion, r=3.5, fixed 50 dmg | Yellow glow |
| Tank | 1.5 | 200 | Slow, high HP | Large scale |
| **Charger** | 2.5 → 6.5 sprint | 55 | 10m trigger → sprint chase → impact explosion, r=4.0, 80→20 falloff | Magenta glow |
| BOSS | 2.0 | 800 | Special abilities (summon / roar / charge) | Red glow, large |

### Wave Modifiers
- **Wave 3**: Swarm — spawn count ×2.5, HP ×0.8
- **Wave 9**: Frenzy — enemy speed ×1.4, damage ×1.5

### Visual & Audio
- Bright white floor, clear visibility
- Enemy self-illumination for type recognition
- Hit marker: "+" turns red "X" for 0.15s on hit
- Camera recoil: 1.5° pitch kick, 0.08s recovery
- Procedurally generated gunshot / hit sounds (no audio files needed)
- Blood particles on zombie hit, wall decals on surface hit (fade out after 2s)

---

## Project Structure

```
ZombieFPS/
├── project.godot          # Project config, main scene = menu.tscn
├── scenes/
│   ├── menu.tscn          # Character select (all drawn via _draw)
│   ├── main.tscn         # Game world root
│   ├── player.tscn        # Player + Head/Camera3D/Gun/Muzzle
│   ├── zombie.tscn        # Zombie base (body assembled at runtime)
│   ├── hud.tscn           # HUD overlay (health/ammo/wave/minimap/BOSS bar)
│   └── grenade.tscn       # Grenade RigidBody3D
└── scripts/
    ├── player.gd          # Player control, weapons, skills, hit detection, audio synth
    ├── zombie.gd          # Zombie AI, body building, type config, BOSS skills
    ├── wave_manager.gd    # Wave spawning, map generation, portal between waves
    ├── hud.gd             # HUD update, hit marker, minimap
    ├── menu.gd            # Character selection UI
    ├── game_state.gd      # Autoload global state
    ├── grenade.gd         # Grenade physics + explosion
    ├── ammo_box.gd        # (reserved, not yet connected)
    └── minimap.gd         # Minimap drawing
```

---

## Development Notes (Lessons Learned)

This project was built through a structured AI-assisted workflow. Key takeaways for Godot 4 beginners:

### 1. Type-Safe Arrays Cause Silent Crashes
**Bug**: `var current_weapons: Array[String] = ["pistol"]` crashed silently when assigned from an untyped dictionary return. Godot 4 stops `_ready()` execution with no obvious error in-game.
**Fix**: Remove the explicit type annotation when the source can return an untyped Array.
**Lesson**: Godot 4 typed arrays are strict — if you see a grey screen after scene load, check script errors first.

### 2. Shared Materials Color All Instances
**Bug**: Setting `albedo_color` on a material in `zombie.tscn` (a sub_resource) changed the color of *all* zombie instances at once.
**Fix**: Set `resource_local_to_scene = true` on the material resource. Each scene instance gets its own copy.
**Lesson**: In Godot 4, resources are shared by default. If you modify a material at runtime and see the effect everywhere, this is why.

### 3. Node Must Be In Tree Before Setting Global Transform
**Bug**: `hole.global_position = pos` before `add_child(hole)` silently failed — node not inside tree means `global_transform` returns identity.
**Fix**: Add child first, then set position.
**Lesson**: Always call `add_child()` before modifying `global_position` / `global_rotation`.

### 4. Defensive Checks for Swapped-Out Nodes
**Bug**: Flamethrower effects crashed when the old gun barrel was `queue_free`'d during weapon swap, but a pending frame still referenced it.
**Fix**: `if not is_instance_valid(muzzle): return` before accessing.
**Lesson**: When using `queue_free()` on a node, always guard references in async / deferred code paths.

### 5. Git Version Control Is Non-Negotiable
With multiple AI agents iterating on the same codebase, a single bad edit could break everything. Git commits after each milestone made rollback trivial.

---

## Known Issues / Roadmap

- [ ] No pickups (ammo boxes / medkits) — `ammo_box.gd` exists but is not connected
- [ ] No upgrade system (three-choice passive upgrade between waves)
- [ ] All visuals are primitive boxes — no animated character models
- [ ] No scoped zoom on sniper rifle
- [ ] BOSS abilities implemented but not extensively playtested
- [ ] No background music

---

## Credits

- Engine: Godot 4.7.1
- Inspired by: *Deathly Stillness* (Steam, free)
- Developed with AI-assisted workflow (DeepSeek + Doubao)
