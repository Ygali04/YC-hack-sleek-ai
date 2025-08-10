# Sleek AI — Your on-call AI game developer

*(alt slogans you can use: “Prototype to playtest, at the speed of thought.” / “From prompt to playable.”)*

Sleek AI is a **Godot 4** plugin that turns natural-language prompts into **scenes, sprites, animations, and GDScript**. It wires up a professional scene hierarchy, keeps assets organized, and stays **idempotent** (no accidental re-generation of files) so you can iterate fast without wrecking your project.

* **LLMs** (code + scene logic) are accessed via **OpenRouter** (API key in a `.env` file).
* **Image generation** (sprites, sprite sheets, tiles) is powered by **OpenAI gpt-image-1** (API key in the same `.env`).
* Built for the standard Godot pipeline: **graybox → mechanics → content → polish**.

---

# Why Sleek AI?

* **End-to-end**: prompts → tilesets → spritesheets → scenes → scripts → a playable level.
* **Godot-native**: uses best-practice nodes, signals, TileMap + TileSet collisions, `CharacterBody2D`, `AnimatedSprite2D`, etc.
* **Deterministic & Idempotent**: never re-creates assets that already exist; uses a MANIFEST and explicit `REGEN:` commands.
* **Opinionated**: imposes clean project structure, naming, and run scene wiring, so teams don’t drown in spaghetti.

---

# What it builds (out of the box)

A compact Mario-style platformer you can extend:

* `Player` with run/jump, variable jump height, coyote/buffer time (optional), animated idle/run/jump.
* `TileMap` + TileSet with **16×16** (or **32×32**) tiles and collision shapes.
* Interactables: `Coin`, `QuestionBlock`, `Brick`, `Pipe`, `Flagpole`, `Checkpoint` (you can toggle which to include).
* Enemies with patrol logic (raycasts, shell/slide or bounce variants).
* `Killzone` with slow-mo death + timed restart.
* `HUD` for score/coins/lives/time bound to a `GameManager` Autoload.
* `Music` as an Autoload scene so tracks don’t restart on death.

You can swap this blueprint for any 2D design; the **workflow** is what matters.

---

# Requirements

* **Godot**: 4.1+ (4.2 recommended)
* **OpenRouter API key** for LLMs
* **OpenAI API key** for images (gpt-image-1)
* Internet access (for model calls)

---

# Installation

1. Copy the plugin folder into your project:
   `res://addons/sleek_gamedev_ai/`
2. In Godot: **Project > Project Settings > Plugins** → enable **Sleek AI**.
3. Create a `.env` at your project root:

```ini
# .env (do NOT commit to source control)
OPENROUTER_API_KEY=sk-or-xxxx
OPENAI_API_KEY=sk-xxxx
OPENAI_ORG_ID=org-xxxx

# optional model preferences
OPENROUTER_MODEL=anthropic/claude-3.7-sonnet-thinking
```

4. Restart Godot (so Sleek AI loads env vars).

---

# Project Layout (enforced)

```
res://
  scenes/          # only .tscn
  scripts/         # only .gd
  assets/
    sprites/       # character/enemy/coins/etc (PNG)
    tiles/         # tilesets + atlases (PNG)
    props/         # blocks, pipes, flag, vfx (PNG)
    ui/            # HUD icons/fonts (PNG/TTF)
  audio/           # your music and sfx (user-supplied)
  addons/sleek_ai/
```

**Naming conventions** (examples):
`Player.tscn`, `Enemy_Goomba.tscn`, `Enemy_Koopa.tscn`, `Coin.tscn`, `Platform.tscn`, `Killzone.tscn`, `HUD.tscn`, `Level1.tscn`, `Main.tscn`.
All code uses **relative** paths (`res://...`).

---

# Scene Hierarchy (baseline)

**Main.tscn** *(Run Scene)*

* `LevelRoot` → instance of `Level1.tscn`
* `HUDRoot` → instance of `HUD.tscn`

**Level1.tscn**

* `TileMap` (+ TileSet collisions)
* `StartPosition` (Marker2D)
* Instances: `Player`, `Coin*`, `Platform*` (static & moving), `Enemy*`, `KillzoneBottom`
* (Optional) `Labels` group of world-space hints

**Player.tscn**

* `CharacterBody2D`

  * `AnimatedSprite2D` (SpriteFrames: idle/run/jump)
  * `CollisionShape2D`
  * `Camera2D` (zoom=4, smoothing on; limits set)

**HUD.tscn**

* score/coins/lives/time bound to `GameManager` (Autoload)

**Music.tscn** *(Autoload)*

* `AudioStreamPlayer2D` (looped; volume via Music bus)

---

# How Sleek AI Works (prompted workflow)

Sleek AI runs in **phases** and **will not skip** ahead:

1. **Skeleton**

   * Creates folders; `Main.tscn` as Run Scene; `GameManager.gd` Autoload (`score, coins, lives, time`, signals).
2. **Graybox Core**

   * `Player.tscn` with minimal visuals and a working controller (`player.gd`).
3. **Level Layout**

   * `Level1.tscn` with `TileMap`; imports tileset; defines collisions.
4. **Interactables**

   * `Coin.tscn`, `Platform.tscn`, `Killzone.tscn` (+ timer / restart).
5. **Enemies**

   * Base enemy + variants; patrol via `RayCast2D`, stomp/shell if requested.
6. **Final Art & Animation**

   * Generates sprites/spritesheets; builds SpriteFrames; replaces placeholders.
7. **HUD & Audio**

   * `HUD.tscn`, bind to `GameManager`; add `Music` Autoload.
8. **Acceptance**

   * Start → play → death → restart; scoring works; no hard locks.

> If an asset is missing, Sleek AI uses a **temporary placeholder** (single-frame PNG) and logs it. It never blocks the build.

---

# Idempotency & Regeneration

* Sleek AI maintains a **MANIFEST** of every file it creates/updates.
* **Rule:** if `res://assets/.../foo.png` exists, Sleek AI **will not** regenerate it unless you explicitly ask.

### Forcing regeneration

Use the directive **inside your prompt**:

```
REGEN: res://assets/sprites/player_knight.png
```

Sleek AI will create `player_knight_v2.png` (or overwrite if you specify `OVERWRITE:`).

### Skipping creation

If you already have an asset/script/scene, say:

```
SKIP: res://scenes/Platform.tscn
```

At the end of each operation, Sleek AI prints:

```
MANIFEST (new/updated):
  - res://scenes/Player.tscn
  - res://scripts/player.gd
  - res://assets/sprites/player_knight.png
```

---

# Image Generation Rules

* **Pixel art**: nearest filtering, no mipmaps, transparent background.
* Spritesheets: grid-aligned frames; rows = animations (e.g., idle/run/jump), with frame counts specified in your prompt.
* Tilesets: 16×16 or 32×32; provide edge/corner variants; Sleek AI adds **TileSet collision polygons** for solid tiles; partial shapes for bridges/ramps when requested.
* If a prior step generated an image, Sleek AI **reuses it** (no duplicate SD calls).

---

# GDScript Standards

* Godot 4 GDScript; signals over polling; small, focused scripts per scene.
* Player input via actions: `move_left`, `move_right`, `jump` (you can bind WASD + arrows).
* Animation state logic lives with the node that renders it (`AnimatedSprite2D`).
* No absolute paths; no editor-only hacks; comments for public methods & states.

---

# Quickstart Prompts (copy/paste)

**1) Initialize project**

```
Create folders and set up Main.tscn as Run Scene. Add GameManager.gd Autoload (score, coins, lives, time; signals coin_collected, life_changed, level_cleared). Output MANIFEST.
```

**2) Player**

```
Generate Player.tscn (CharacterBody2D + AnimatedSprite2D + CollisionShape2D + Camera2D). Write player.gd with gravity, run/jump, variable jump, coyote time. Bind actions: move_left, move_right, jump. Add idle/run/jump SpriteFrames (use placeholders). Output MANIFEST.
```

**3) Level & tiles**

```
Create Level1.tscn with TileMap (16x16). Generate tileset (grass, dirt, edges, bridge) or use existing. Define collisions for solid tiles and partial shapes for bridge. Instance Player at StartPosition. Output MANIFEST.
```

**4) Interactables**

```
Create Coin.tscn (Area2D + AnimatedSprite2D + CollisionShape2D + AnimationPlayer + AudioStreamPlayer2D). Connect to GameManager.add_point(). Add pickup animation to hide/disable, play sfx, then queue_free. Output MANIFEST.
```

**5) Enemy & kill**

```
Create Killzone.tscn (Area2D + Timer; body_entered slows time, removes player collider, restarts on timeout). Create Slime.tscn (Node2D + AnimatedSprite2D + instance Killzone + CollisionShape2D + RayCast2D L/R). Write slime.gd: patrol, flip on ray hits or edge. Output MANIFEST.
```

**6) Final art pass**

```
Generate pixel-art spritesheets (32x32 or 16x16): player idle(4)/run(8–12)/jump(1), coin spin(6–12), slime idle(4); keep prior file names; do not regen existing. Build SpriteFrames in Player/Coin/Slime scenes. Output MANIFEST.
```

**7) HUD & audio**

```
Create HUD.tscn with labels bound to GameManager. Create Music.tscn (AudioStreamPlayer2D, loop). Register Music as Autoload. Output MANIFEST.
```

---

# Configuration

* **Models** (via env):
  `OPENROUTER_MODEL` can be any OpenRouter model slug (e.g., `openai/gpt-4.1-mini`, `anthropic/claude-3.7-sonnet-thinking`, `meta-llama/llama-3.1-70b-instruct`).
  `SD_MODEL` can be any supported Stable Diffusion endpoint (e.g., `stability/sd3-medium`).

* **Tilesize**: set in your prompt (`16×16` default).

* **Resolution & camera zoom**: commonly 1280×720 with `Camera2D.zoom = 4` for crisp pixel art.

---

# Tips & Best Practices

* **Graybox first**: accept placeholder art until mechanics feel right.
* **Instance scenes**, don’t sprinkle raw nodes across Main.
* **Editable Children** sparingly—prefer editing the source scene.
* Keep **Player z\_index = 5** so it draws above platforms.
* Don’t commit `.env`. Do commit **MANIFEST**.
* Use `REGEN:` only when you truly want a new file or overwrite.

---

# Troubleshooting

* **“I can’t see my scenes under Main.”**
  You must **instance** them into `Main.tscn` (drag `Level1.tscn`, `HUD.tscn` into Main). Opening a scene in the editor does **not** instance it.

* **Generated asset not crisp**
  Ensure import: Filter **Nearest**, Mipmaps **off**. In Project Settings: Rendering → Textures → Default Filter **Nearest**.

* **Music restarts on death**
  Make `Music.tscn` an **Autoload**.

* **Coin triggered by platform**
  Put Player on its own physics **layer**; set Coin’s mask to detect only that layer.

* **Sleek AI keeps re-making a file**
  Add the existing path to MANIFEST or use `SKIP: res://path`. To force, use `REGEN:` explicitly.

---

# Roadmap

* 3-lane “preset” templates (platformer, top-down, action RPG).
* Built-in tileset/effects packs.
* Multi-scene level streaming + checkpoint saves.
* Sprite rig/retarget for consistent character sets.
* Test harness for scripted playthroughs.

---

# Security & Privacy

* API keys live in `.env`. **Never** commit them.
* Prompts and file names may be sent to providers; avoid sensitive content.
* You own your generated assets—check your model provider’s license terms.

---

# License

* Plugin: choose a license that fits your distribution (MIT/BSD/Apache-2.0 recommended for tools).
* **Generated art**: subject to your SD provider’s license.
* **Third-party assets** you import: follow their licenses (e.g., CC0/CC-BY).

---

If you want a **ready-to-paste system prompt** for the plugin UI that encodes this workflow and idempotency rules, say the word and I’ll drop a lean version you can set as the default.
