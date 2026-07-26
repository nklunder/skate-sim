# 🤖 AGENTS.md - Skate Sim V2 Knowledgebase & Session Ledger

> **IMPORTANT INSTRUCTION FOR ALL AI AGENTS:**  
> 1. **Read First:** At the beginning of any new chat session or when resuming work on this repository, you **MUST read this `AGENTS.md` file first** to synchronize your understanding of the architecture, design philosophy, and progress.  
> 2. **Auto-Update Protocol:** You **MUST automatically update this file** immediately whenever:
>    - The user provides corrective feedback or refines game feel/rules.
>    - Architectural or design decisions are established (e.g., via `/grill-me` interviews).
>    - New features, trick mechanics, or physics adjustments are deployed and verified.
>    - A new known bug or feature request is identified or resolved.
> 3. **Validation Routine:** Whenever scripts are edited, proactively execute headless validation using `/Applications/Godot.app/Contents/MacOS/Godot --headless --quit` before reporting completion.

---

## 🛹 Project Vision & Control Philosophy
**Skate Sim V2** is an authentic, physics-driven skateboarding simulator built in Godot 4.7 (Vulkan Forward+), designed around anatomical foot control, weighted physical responsiveness, and state-of-the-art procedural animation.

### Core Control Tenets
- **Anatomical Foot Mapping:** Analog thumbsticks correspond directly to physical feet:
  - **Left Stick = Left Foot** (Blue shoe box)
  - **Right Stick = Right Foot** (Red shoe box)
- **Universal Trick Rule:** Whether riding **Regular Forward, Switch, Nollie, or Fakie**:
  - Controls always map directly to the foot physically sitting over the active nose or tail.
  - **Flics Outward** (away from toes, behind the body plane) = **Kickflip**.
  - **Flices Inward** (toward toes, in front of the body plane) = **Heelflip**.
- **Scoop & Shove-it Symmetry:** The skateboard kicks directly in the true rotational direction of your thumbstick sweep, completely independent of starting position on the joystick or physical deck alignment.
  - **Standard Scoop Buffer ($40^\circ \to 94^\circ$ arc span):** Triggers a **$180^\circ$ Pop Shove-it** (or Varial Flip).
  - **Deep Scoop Buffer ($\ge 95^\circ$ arc span):** Triggers a **$360^\circ$ Pop Shove-it** (or 360 Flip / Tre Flip, Laser Flip), reducing required thumbstick rotational effort while avoiding accidental misfires.
- **Analog Trigger Body Rotation:** L and R trigger pulls spin the skater in mid-air. An **audio-log power taper curve ($y = \text{sign}(x) \cdot |x|^{2.2}$)** desensitizes light-to-mid squeezes for subtle styling adjustments while scaling exponentially to 100% spin velocity (`554 deg/s`) for explosive flat-ground 360s!

---

## 🛠️ Key Files & System Architecture

### 1. `res://scripts/player/SkaterController.gd` (3-Layer Kinematics & Touchdown Engine)
- **Layer 1 (Body Spin Authority):** Trigger lean rotates `board_pivot.y` directly (with fluid angular momentum lerping `lerp 20.0 * delta`) so the rolling travel vector and chase camera stay anchored cleanly behind the rider. Pre-wind steering on the ground is damped by 80% during pop loading.
- **Layer 2 (Airborne & Grounded Pitch Control):** Thumbsticks tilt the nose/tail between `0.20 to 0.90` stick deflection for manuals ($24^\circ$ tilt) and airborne realignments.
- **Layer 3 (Deck Flip & Spin Authority):** `board_mesh.z` (roll) and `board_mesh.y` (yaw) rotate cleanly toward targets. Shoe hover catching raises shoe boxes to $Y=0.18\text{m}$ during flips, locking in as griptape revolves face up. Both shoe coordinates firmly snap back to deck rest pose immediately upon touchdown and maintain locked standing posture during grounded rolling whenever not executing a foot push stroke.
- **Touchdown Tolerances:**
  - **Manual Catch Zone:** Landing within $\pm 15^\circ$ pitch while holding middle stick zone ($0.20 \to 0.90$) bypasses entry delays for instant, silky manual rollouts.
  - **Sideways Landing Window ($\pm 45^\circ$):** Touching down within $\pm 45^\circ$ of straight ($0^\circ/180^\circ$) snaps to orientation. Landing sideways perpendicular to travel direction ($45^\circ \to 135^\circ$ or $225^\circ \to 315^\circ$) fires a `"BAIL! (Sideways Landing / Wheel Skid)"` speed crash!
- **Simulation Speed Calibration:** Cruising max speed is calibrated to `7.0 m/s` ($\approx 15.7\text{ mph}$) with `2.0 m/s` foot pushes and `608 deg/s` flip rotation speeds for readable, floaty trick execution.

### 2. `res://scripts/input/FootInputState.gd` (Input Classification & Trick Nomenclature)
- **Stance Tracking:** Dynamically evaluates `leading_foot` and `trailing_foot` using travel velocity dot product when moving, or static SkaterController forward orientation (`-pivot.get_parent().global_transform.basis.z`) when stationary. This ensures 100% accurate switch foot recognition even when standing completely still!
- **Arc Sweep Measurement (`max_swept_angle`):** Accumulates frame-to-frame `angle_difference` deltas **in degrees** (`accumulated_scoop_deg`) during pop loading (`LOADING_OLLIE`/`LOADING_NOLLIE`) to separate quarter-circle from half-circle scoops.
- **Trick Measurement:** `_build_trick_signature()` populates `current_trick` (a `TrickSignature`) with pop / flip / shuv. It builds **no display strings** — naming happens at touchdown in `SkaterController._finalise_trick_name()`.
- **Push Grammar:** `Mongo Push (Leading)` / `Standard Push (Trailing)` classification remains string-based (display only).

### 2a. 🏷️ Trick Naming (`res://scripts/tricks/`)
- **`TrickSignature.gd`** — measurement of what physically happened: `pop`, `flip`, `shuv_deg` (board **relative to the body**), `body_deg`, plus derived `board_world_deg` (= body + shuv), `body_with_shuv`, `lands_switch`. `describe()` returns the HUD readout.
- **`TrickNames.gd`** — the editable `TABLE` and `resolve()`. **This is the only file to edit to add or rename a trick.**
- **CORE PRINCIPLE:** the engine **encodes no skateboarding naming conventions**. It never decides what is frontside, whether fakie reverses labels, or whether nollie keeps them. It measures the action; the table assigns the name. Skate naming has too many one-off rules (reference material consulted during design contradicted itself on the fakie case) for correctness to depend on the engine interpreting them.
- **Authoring workflow:** do the trick, read the `Signature:` line off the DebugHUD, paste those values into `TABLE` with the name you want. No reasoning about rotation conventions required.
- **RULE — count spin in `world`, not `shuv`, when authoring rows.** `shuv` is board rotation *relative to the body*; `board_world` (= shuv + body) is what the board actually turns. A trick described as "360 degrees of spin" is 360 of **world** rotation, and a simultaneous 180 body rotation supplies half of it — so a **Bigflip** is `shuv = -180, body = -180` (world -360), **not** `shuv = -360`. The whole bigspin family is one motion (board 360 world, body 180) with the flip deciding the name: no flip → Bigspin, kickflip → Bigflip, heelflip → Bigspin Heelflip.
- **RULE — unlisted fields must be inert.** In a rule, any of `flip` / `shuv` / `body` you omit **must be zero** to match. This stops `{shuv = -360, flip = KICK}` ("360 Flip") from silently swallowing a 360 flip that also had a body rotation. `pop` is the exception (omit it and the row covers all four stances with the stance added as a prefix); derived fields are opt-in; write `ANY` to explicitly ignore a field.
- **RULE — ⚠️ THE #1 SOURCE OF BUGS: the two rotations are measured in DIFFERENT FRAMES.** Every naming bug so far has been one rotation stored as if it were in the other's frame. The failure is silent: nothing crashes, the trick just resolves to its mirror image. Both conversions live in `TrickSignature.gd` and **nowhere else**:

| Quantity | Measured in | Already rider-relative? | Converter |
|---|---|---|---|
| `shuv_deg` | thumbstick sweep | **Yes** for facing (sticks map anatomically to feet) | `shuv_sign(is_goofy, left_foot_scoops)` — the scooping stick is **right** for Ollie/Fakie but **left** for Switch/Nollie, so an identical sweep means the opposite board direction |
| `body_deg` | **world** yaw of `board_pivot` | **No** | `body_sign(is_goofy, riding_reversed)` — riding switch/fakie puts the rider's frontside the other way round in the world |

  `riding_reversed` is sampled from the pivot's real yaw at pop (`cos(deg_to_rad(board_pivot.rotation_degrees.y)) < 0.0`, the same idiom as `deck_reversed`) rather than inferred from the pop type, and captured at pop because the yaw changes in flight.
- **RULE — the engine guarantees CONSISTENCY, not polarity.** Which direction is called "frontside" is a naming choice owned by `TABLE`. The invariant the code must hold is that one felt trick yields one signature across all stances and facings; `mirror_test` asserts exactly that, and additionally pins the regular/forward case so a future sign fix cannot silently invert an already-calibrated table.
- **RULE — naming happens at touchdown, never at pop.** Body rotation accrues *during flight* (`airborne_body_yaw_deg`), so tricks defined partly by body rotation (bigflip, frontside flip, body varial) cannot be named at pop. Mid-air status shows no trick name. Bails leave the previous landed trick on display.

### 3. `res://scripts/player/SkateDeckMesh.gd` (3D Skateboard Model & Material Engine)
- Extends `Node3D` and instantiates the imported `res://skateboard.blend` asset to replace the former procedural placeholder deck.
- Applies precision scale calibration (`0.1722`) and centering offsets (`Vector3(-0.3239, -0.3585, 0.1169)`) to align directly with an 80 cm real-world deck sitting under the skater's shoes at `Y = 0.055m`.
- Features an inspector flag (`use_low_poly`, **default `true`**) to prevent Z-fighting between overlapping high/low poly meshes from Blender, and automatically assigns high-contrast, authentic skate materials (aluminum trucks, cream polyurethane wheels, and orange bushings).
- **LOD Tiers:** the high tier is **646,208 tris**, the low tier **8,328** — a `77.6x` difference that is visually indistinguishable at gameplay range, so the low tier is the shipping default. 65% of the high tier is spent on `bearings_high` (253,952) and `bolts_high` (164,928), parts that are sub-pixel at chase distance; `board_high` itself is only 79,040. Cause is Bevel + Subdivision modifiers baked at export on every `_high` object.
- **CAVEAT:** `use_low_poly` only controls `visible`, so both tiers are still instanced and **654,536 tris remain resident in memory**. The flag removes draw and shadow-pass cost, *not* load cost or the 22.7 MB `.scn` / 25.9 MB `.bin` import footprint. Reclaiming that needs the high tier stripped from the `.blend` or split into a separate asset.
- The low tier ships **no `TANGENT`** in the glTF, but `meshes/ensure_tangents=true` synthesizes them on import, so `deck_two_tone.gdshader` runs on it unmodified. The two tiers have inverted UV density (`board_low` is 2x denser across the width, ~half along the length) yet the grit reads identically — measured high-frequency RMS `7.5` vs `7.4` — so `grip_grain_scale` needs no per-tier retuning.
- **Two-Tone Deck (`res://resources/deck_two_tone.gdshader`):** The deck is driven by a `ShaderMaterial` rather than flat surface colors, exposing `grip_color`, `deck_bottom_color`, `bottom_emission`, `facing_sharpness`, and the `grip_grain_*` set as inspector properties.

### 3a. ⚠️ Deck Material Constraint: The Board Is One Surface
- `skateboard.blend` ships **no materials, no textures and no vertex colors** — the only material datablock is Blender's default `Dots Stroke` grease pencil, every mesh has `slots=0`, and the import uses placeholder materials (`blender/materials/export_materials=1`). All deck colour therefore lives in GDScript/shader code, **never** in the `.blend`.
- `board_high` exports 3 surfaces, but they do **not** map to grip/wood/edge. Surface 0 is the *entire* deck shell — top (area 4.98), bottom (area 5.03) and rails together — while surfaces 1-2 are hairline slivers (area 0.0098 and 0.0079) generated by stray out-of-range material indices (`28360`, `21808`) on a mesh with zero slots.
- **RULE:** Because top and bottom share one surface, they can never be separated with per-surface materials. The split is done per-fragment off the model-space normal (mesh-local **+Y is up**; the 180° Y node rotation on `board_high` leaves the up axis intact), so it rides along correctly through every flip, shuv and manual. All surfaces receive the same shader.
- The grit is deliberately faded out via `fwidth` once a noise cell drops below a pixel, so the deck reads as textured up close and as clean matte black at chase distance instead of aliasing into shimmer.

### 4. `res://scenes/player/SkaterRig.tscn` (Scene Tree & Visual Debugger)
- Contains `BoardPivot`, `BoardMesh`, truck contact raycasts, foot nodes (`LeftFoot`, `RightFoot`), and `CameraPivot`.
- Foot meshes are sized to roughly a **size US 11 M shoe** (`28.0 cm` length, `9.8 cm` width, `3.8 cm` height) with flush rounded sneaker toe tips (`ToeTip` cylinder child nodes at `X = 0.1155m`, radius `0.049m`).
- Features anatomical standing ankle poles (`PegPivot` shifted $-0.075\text{m}$ over heel articulation at `Y = 0.019m`) that stand upright vertically at rest and dynamically tilt up to `peg_tilt_deg` ($35^\circ$) during joystick deflections.
- Feet run along **local X** (toe at $+X$, heel at $-X$) and are seated at `X = -0.025m` so the heel edge pulls out over the heel rail and more of the toe sits on the deck — overhang is balanced at `0.043m` heel / `0.042m` toe (previously `0.018m` / `0.067m`).
- **RULE:** `left_foot_rest` / `right_foot_rest` are captured from this scene in `SkaterController._ready()`. Never re-hardcode them in script — duplicating the values silently reverted any scene-set foot offset the moment a push stroke finished.
- Chase camera sits closer at `Y = 1.25m, Z = 2.1m` behind the rider tilted down $25^\circ$ for intimate trick and deck visibility.

---

## ⚠️ Critical Technical Notes & Architectural Rules
1. **Godot Euler Rotation Inversion ($\text{Y} = 180^\circ$ Compensation & Shove-it Decoupling):**
   - Because Godot uses `YXZ` Euler rotation order, turning the skateboard $180^\circ$ into Switch or Fakie flips the direction of the local X and Z axes relative to global world space.
   - **RULE:** Always apply stance sign compensation (`stance_sign = -1.0 if not left_is_front else 1.0`) when setting local X pitch targets for pops and manuals. For flip roll targets, decouple rotation from $180^\circ$ deck yaw reversals after Shove-its (`deck_orientation_comp = -1.0 if cos(deg_to_rad(board_mesh.y)) < 0.0 else 1.0`) and invert roll exclusively for Nollie pops (`-1.0`). For Shove-it and Varial spin yaw targets around Y, NEVER couple rotation to `deck_orientation_comp` or physical deck reversal — the spin sign is simply `input_state.last_scoop_sign`, the raw rotational direction of the thumbstick sweep, matching the Core Tenet above. In Fakie stance, swap Kickflip/Heelflip trick labels in `FootInputState.gd` to print correct terminology while preserving control-to-rotation kinematics.
2. **Modular Speed Parameters:**
   - Always derive motion rates from top-level exported variables (`flip_speed_deg`, `spin_speed_deg`, `body_spin_speed_deg`, `max_push_speed`, `push_impulse`, `rolling_friction`, `peg_tilt_deg`). Never hardcode velocity literals inside tick equations.
3. **Never Read a Display String to Drive Behaviour:**
   - Trick *physics* must key off `input_state.current_trick` (`sig.pop == …`, `absi(sig.shuv_deg) == 360`), never off `last_combo_string` or `active_spin_type`. Before this rule existed, `SkaterController` read `last_combo_string.contains("360")` / `.contains("Laser")` to pick spin degrees and spin velocity, so renaming a trick silently halved the board's spin speed.
   - **RULE:** `last_combo_string` and `last_pop_type` are **display only**. Regression-tested: a trick named `"360 Laser Flip"` carrying a 180 shuv still spins exactly 180.
   - ⚠️ `active_flip_type` is **not** display-only despite the name — it is the working variable inside `_build_trick_signature()` that the Fakie Kickflip/Heelflip swap mutates before it is matched into `sig.flip`. Deleting it as "cosmetic" silently breaks Fakie flip naming. (`active_spin_type` genuinely is dead: written, never read.)
4. **Screen-Space Debug Visualizers vs. `BoardPivot` Yaw:**
   - `CameraPivot` is parented to `SkaterRoot`, **not** `BoardPivot`, so it does not inherit the $180^\circ$ Switch/Fakie yaw. Any visualizer parented under `BoardPivot` that is meant to depict raw gamepad input therefore mirrors in switch (stick down reads as up, left as right).
   - **RULE:** Resolve the stick vector onto the pivot's local axes through `board_pivot.rotation.y` (`local_x = x*cos - y*sin`, `local_z = x*sin + y*cos`) rather than applying a stance sign flip. This stays correct at *any* yaw, so the pegs remain honest part-way through an aerial spin, not only at $0^\circ$ and $180^\circ$. Verified exact at $0/90/180/270^\circ$; composing the two Euler tilts leaves a harmless ~$3^\circ$ deviation at intermediate yaws such as $45^\circ$.

---

## 📈 Current Progress & Session History
- [x] **Phase 0 & 1:** Foundation kinematics, stance detection, face-button pushing (Standard vs. Mongo), and manual balance tolerance zones.
- [x] **Phase 2 & 3:** 3-layer pop jump physics, shoe hover catching, Kickflip/Heelflip flick classification, and Shove-it rotation alignment.
- [x] **Visual Polish & Debugger:** Procedural parabolic concave deck mesh, anatomical standing ankle pegs with joystick tilt, and rounded sneaker profiles.
- [x] **Trigger Physics & Precision Landings:** Calibrated body rotation speed (`554 deg/s` for flat-ground 360s), audio-log trigger sensitivity curve (exponent `2.2`), 80% pre-wind turning suppression during pop loading, fluid angular momentum smoothing, and $\pm 45^\circ$ sideways landing bail tolerances.
- [x] **Advanced Shove-its & Gameplay Pace:** Integrated dynamic arc span tracking for Quarter-Turn ($180^\circ$) vs. Half-Turn ($360^\circ$) Shove-its, automatic Tre Flip / Laser Flip recognition, and global 80% simulation speed calibration.
- [x] **Switch Stance & Manual Inversion Resolution:** Solved stationary switch stance reversal by testing against static forward vectors at zero velocity, and applied Euler rotation angle inversion for all Switch/Fakie manuals, pops, and flips.
- [x] **Top Speed Calibration Update:** Adjusted cruising max speed (`max_push_speed`) from `5.6 m/s` to `7.0 m/s` ($\approx 15.7\text{ mph}$) and exported motion physics parameters in `SkaterController.gd`.
- [x] **Shove-it Scoop Sensitivity Refinement:** Lowered the 360 Shove-it / Tre Flip trigger threshold from `110°` down to `80°` for more effortless quarter-turn sweeps, and exported both `shuv_180_threshold_deg` and `shuv_360_threshold_deg` in `FootInputState.gd`.
- [x] **Skateboard 3D Model Integration:** Replaced the procedural placeholder skateboard with the imported `res://skateboard.blend` model in `SkateDeckMesh.gd` and updated `SkaterRig.tscn` to use `Node3D` for `BoardMesh`. Implemented calibrated scaling, centering offset, LOD deduplication, and automated material surfacing.
- [x] **Data-Driven Trick Naming:** Replaced the string-concatenation naming tree with a measured `TrickSignature` plus an editable rule table (`scripts/tricks/`). Names now resolve at **touchdown** rather than at pop, so body rotation counts — making bigflip, frontside flip and body varial expressible for the first time. Severed the display-name→physics coupling that let a rename change board spin speed. Follow-up fixes in the same session corrected two silent mirror-image bugs: the shuv sign (the scooping foot swaps ends between stances) and the body sign (body rotation is measured in world space and needs flipping when riding reversed). Verified headlessly across six suites — naming table, signature stability, stance consistency, mirror invariant, physics decoupling, and end-to-end pop→flight→landing including bail behaviour.
- [x] **Low-Poly LOD Default:** Flipped `use_low_poly` to `true`, dropping drawn geometry from `646,208` to `8,328` tris (`77.6x`) with no visible change at chase or underside distance. The two-tone deck shader carries over to `board_low` unmodified.
- [x] **Foot Seating & Ankle Peg Direction Fix:** Pulled the placeholder foot meshes out to `X = -0.025m` so the heel edge clears the heel rail and more of the toe sits on the deck (overhang balanced to `0.043m` / `0.042m`), and moved rest-pose capture into `SkaterController._ready()` so `SkaterRig.tscn` is the single source of truth. Fixed the ankle pegs reading reversed in Switch stance by resolving the stick vector through `board_pivot.rotation.y` instead of driving pivot-local degrees directly — headless-verified exact at $0/90/180/270^\circ$ yaw for both feet and all four stick directions.
- [x] **Two-Tone Deck for Trick Readability:** Replaced the flat griptape-coloured deck (which rendered the underside the same near-black as the top) with `deck_two_tone.gdshader`. Griptape black stays on the standing side while the underside runs high-visibility orange (`Color(0.95, 0.30, 0.02)`) so board rotation reads clearly mid-air. Includes a procedural two-octave griptape grain driven mainly by normal perturbation (near-black albedo has too little value range to carry the texture on colour alone) and a `bottom_emission` floor of `0.30`, since airborne the underside falls to ambient-only lighting and sinks to muddy brick exactly when the spin most needs reading.
- [x] **Foot Mesh Refinement & Camera Pull-In:** Sized foot meshes to US 11 M dimensions (`28 cm` long by `9.8 cm` wide, `3.8 cm` tall), adjusted heel peg articulation offsets (`-0.075m`), and pulled the chase camera closer (`Y = 1.25m, Z = 2.1m`) for improved deck and foot visibility.
- [x] **Stance Flip Direction & Shove-it Decoupling Fix:** Decoupled trick spin/flip rotation from $180^\circ$ deck yaw reversals after Shove-its in `SkaterController.gd`, inverted roll directions to correct backward Nollie and Switch flips, and corrected backwards HUD trick name labeling for Fakie kickflips/heelflips in `FootInputState.gd`.
- [x] **Varial & Shove-it Spin Direction Decoupling Fix:** Removed board orientation coupling (`deck_orientation_comp`) from `spin_sign` in `SkaterController.gd`. Unlike flip roll (Z-axis), horizontal yaw spins (Y-axis) must remain strictly independent of the wooden board's $180^\circ$ orientation, ensuring consistent clockwise/counterclockwise scoops relative to the skater when leaping off the nose versus tail.
- [x] **True Angular Sweep & Shove-it Buffer Refinement:** Upgraded Shove-it scoop detection from static stick coordinates to signed rotational sweep direction (`angle_difference`) in `FootInputState.gd` and `SkaterController.gd`. Set generous quarter-turn ($45^\circ \to 134^\circ$) and half-turn ($\ge 135^\circ$) buffer windows so starting position on the thumbstick circle no longer affects rotation accuracy.
- [x] **Frame-Delta Sweep Accumulator & Effortless 360 Shuv Calibration:** Solved occasional inverted 360 Shove-it spin animations by replacing static `angle_difference(start, current)` with frame-to-frame delta accumulation (`accumulated_scoop_deg += frame_delta`), completely preventing half-circle wrap-around bugs when sweeps exceed $180^\circ$. Lowered the 360 Shove-it trigger threshold from $135^\circ$ to $95^\circ$ and 180 Shove-it threshold to $40^\circ$ for smooth, effortless execution (with further testing and refinement noted as a possible next step).
- [x] **Universal Touchdown Foot Settlement & Grounded Posture Maintenance:** Resolved a bug where shoes hovered above the board after landing a trick until a new input occurred. Because downward foot lerping lived exclusively inside the airborne loop (`if not is_grounded`), touching down before the lerp completed froze the shoes in mid-air. Implemented instant foot coordinate reset right at touchdown (`_evaluate_touchdown_landing`) and persistent standing posture enforcement during idle rolling on pavement (`if active_push_foot == ""`) in `SkaterController.gd`.

---

## 🐛 Known Bugs
- **Active Bugs:** *None currently reported.*
- ⚠️ **Switch/Fakie sign errors are this project's recurring bug class** — do not assume "validated" means immune. Three separate ones surfaced in a single session (reversed ankle pegs, inverted shuv naming, inverted body-rotation naming), each found by *play*, not by tests, because each fails silently as a mirror image rather than an error. When touching anything rotational, check it in all four of {regular, goofy} × {forward, switch/fakie} before calling it done.

---

## 🎯 Pending Feature Requests & Next Milestones
1. **Dynamic Camera Follow & Speed-Based FOV Scaling:**
   - *Goal:* Replace static follower camera with smooth spring-damper camera interpolation.
   - *Behavior:* Scale camera FOV dynamically based on rolling velocity (from ~75° at stationary rest up to ~88° at top cruising pace) to accentuate speed immersion without introducing motion sickness.
2. **Audio Feedback System (Future Phase):**
   - *Goal:* Integrate procedural skate audio sounds (polyurethane wheel roll hum on pavement, crisp maple tail crack pop impulses, griptape catch thuds, and wheel skid screeches on sideways touchdown bails).
