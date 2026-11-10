# Crown & Banner: Ashes of Veyr

**Phase 1 — playable battle prototype** for Godot 4. A touch-first, landscape real-time battle between the Grey March and the Red Fen. All current battlefield graphics are original, code-drawn pixel-style placeholders; no third-party art, audio, or game assets are used.

> This repository currently implements Phase 1 only. It is a small, playable prototype, not yet the full grand-strategy game described in the longer roadmap.

## Run it

1. Install **Godot 4.2 or newer** (standard build; no plugins or imported assets required).
2. Open Godot Project Manager → **Import** and select this folder's `project.godot`.
3. Press **F6** to run the current scene or **F5** to launch the project.
4. On desktop, mouse input mirrors touch for development. The game itself has no keyboard-dependent controls.

The project uses Godot's **GL Compatibility** renderer and a 1280×720 landscape canvas, stretched to the device viewport.

## Phase 1 gameplay

- Two opposing armies, each with four regiments: spearmen, archers, heavy infantry, and cavalry.
- Regiment selection, tap-to-order movement, drag-to-move, target tapping, attack/hold/charge/fire-at-will orders, and rally.
- Real-time deterministic-seed combat simulation, melee and ranged damage, ammunition, morale, routing and rallying, retreat, and battle outcome.
- Battle pause, half-speed, 1×/2× speed, touch-friendly unit cards and order buttons, and a compact battle autosave record.
- Original procedural battlefield details, unit silhouettes, faction colors, banners, morale bars, and battle HUD.

## Touch controls

| Gesture / button | Action |
| --- | --- |
| Tap a friendly regiment / unit card | Select it |
| Tap open battlefield | Move selected unit to that point |
| Drag from a friendly regiment | Move it to the drag destination |
| Tap an enemy regiment | Order the selected unit to engage |
| **ATTACK** | Engage nearest enemy |
| **HOLD** | Hold position; engage nearby attackers |
| **CHARGE** | Close with a temporary charge-speed boost |
| **FIRE AT WILL** | Missile regiment engages at range (melee units fall back to attack) |
| **RALLY** | Restore some selected regiment morale |
| **Ⅱ / ▶** | Pause or resume |
| **SLOW** | Set simulation to half speed |
| **SPEED** | Toggle 1× and 2× |
| Two-finger pinch / drag | Zoom and move the view |

All key buttons are at least 48×48 logical pixels. Desktop mouse controls are included only as a convenient development/testing fallback.

## Project structure

```text
project.godot          Godot project settings, landscape viewport, mobile renderer
scenes/main.tscn       Main battle scene
scripts/battle.gd      Battle setup, touch input, simulation, drawing, and HUD
data/units.json         Data-driven regiment templates and combat stats
tests/combat_smoke_test.gd  Headless unit-data smoke test
```

(The actual data directory is `data/`.) The core prototype intentionally uses one scene script to keep Phase 1 immediately runnable; combat data is separate in JSON. As later phases add campaign systems, logic will be split into reusable components and data files.

## Pixel-art placeholder specs

The prototype draws its sprites from pixel-aligned rectangles, rather than shipping raster sprite sheets. This keeps all placeholder art replaceable and avoids licensing or import setup.

- **Logical sprite cell:** 16×24 pixels per foot soldier; 24×24 horse and rider silhouette. Rendered with nearest-neighbor-style hard edges.
- **Formation rendering:** a regiment is represented by 20 tiny soldier silhouettes; its card shows the full in-world regiment size (32–48 soldiers).
- **Palette:** muted earth/field colors (`#657757`, `#76664e`), steel and linen (`#a99e84`, `#ddd0ae`), and two faction cloths (Grey March blue-grey, Red Fen dark red). Each unit uses a small subset of the palette.
- **Distinct silhouettes:** spears have a long upright spear; archers carry a bow/quiver shape; infantry carry a sword; cavalry appear mounted. Faction standards and colors distinguish sides.
- **Animation:** currently static formation poses with real-time positional movement, impact flash, and routing behavior. Actual 8-direction idle/walk/run/attack/block/hit/death/rout sprite sheets are planned, not implemented.
- **Lighting/weather/audio:** static ambient field shading only. Dynamic lighting, seasons, particles, weather, music and SFX are planned.

For production art, replace the drawing helpers in `scripts/battle.gd` with an atlas (e.g. 128×192 per 8-direction/8-action character sheet, 16×24 frame cells) using nearest filtering. The current primitives are intentionally not represented as finished high-resolution pixel art.

## Android APK / AAB export

1. In Godot, install the matching **Export Templates** (Editor → Manage Export Templates).
2. Install Android Studio / Android SDK and configure Godot's Editor Settings → **Export → Android** with the SDK path and Java SDK path. Use the JDK version recommended by the Godot version in use.
3. Project → **Export** → Add… → **Android**. For a test build, configure the debug keystore if requested, then choose **Export Project** and save an `.apk`.
4. For Play Store distribution, enable **Runnable** as appropriate, configure a release keystore/signing credentials in the Android preset, and export an `.aab` (Godot 4 Android preset supports Gradle build options; use the format selector in the export dialog).
5. Keep orientation landscape; the project requests landscape via `window/handheld/orientation`. Test touch input and safe-area behavior on-device before release.

Export settings and Android SDK UI can vary slightly across Godot 4.x releases. The preset's validation messages identify missing SDK components. iOS export requires macOS and Xcode; add an iOS preset in Godot, configure signing/team settings, export the Xcode project, then build/sign from Xcode. This environment has no Godot executable or mobile signing toolchain, so APK/iOS artifacts have not been generated here.

## Save data

After a battle ends, a compact outcome record is written to `user://battle_autosave.json` (Godot's per-user application data folder). The current Phase 1 prototype does not yet restore a full in-progress battle or expose multiple slots.

## Validation

The project files and JSON are intended for Godot 4.x. The GDScript has been formatted and parsed with `gdformat`; this environment does not include the Godot engine, so a native engine run and APK build could not be verified here.

## Done vs planned

**Done in Phase 1:** playable 2-army battle; data-driven initial regiment stats; touch/mouse selection and movement; basic melee/ranged combat; morale, rout, rally; command buttons; speed/pause controls; original code-drawn art and responsive HUD.

**Planned for later phases:** formations and unit avoidance; flanking/terrain/weather; improved battle AI and pathfinding; campaign/provinces/economy/diplomacy/technology; siege battles; detailed animation atlases and audio; tutorial/localization/settings; save slots and resume; performance profiling and signed Android/iOS builds.

## Original setting

Veyr is a fictional continent. The Grey March keeps the river roads with disciplined spearmen and a blue-grey banner. The Red Fen's warbands answer with iron discipline, field bows, and dark-red standards. The setting, names, UI, and current art are original to this prototype.
