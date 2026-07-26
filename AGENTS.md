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
  - **Quarter-Turn Buffer ($45^\circ \to 134^\circ$ arc span):** Triggers a **$180^\circ$ Pop Shove-it** (or Varial Flip), providing generous over/under tolerances around a standard $90^\circ$ quarter-turn.
  - **Half-Turn Buffer ($\ge 135^\circ$ arc span):** Triggers a **$360^\circ$ Pop Shove-it** (or 360 Flip / Tre Flip, Laser Flip) around a standard $180^\circ$ sweep.
- **Analog Trigger Body Rotation:** L and R trigger pulls spin the skater in mid-air. An **audio-log power taper curve ($y = \text{sign}(x) \cdot |x|^{2.2}$)** desensitizes light-to-mid squeezes for subtle styling adjustments while scaling exponentially to 100% spin velocity (`554 deg/s`) for explosive flat-ground 360s!

---

## 🛠️ Key Files & System Architecture

### 1. `res://scripts/player/SkaterController.gd` (3-Layer Kinematics & Touchdown Engine)
- **Layer 1 (Body Spin Authority):** Trigger lean rotates `board_pivot.y` directly (with fluid angular momentum lerping `lerp 20.0 * delta`) so the rolling travel vector and chase camera stay anchored cleanly behind the rider. Pre-wind steering on the ground is damped by 80% during pop loading.
- **Layer 2 (Airborne & Grounded Pitch Control):** Thumbsticks tilt the nose/tail between `0.20 to 0.90` stick deflection for manuals ($24^\circ$ tilt) and airborne realignments.
- **Layer 3 (Deck Flip & Spin Authority):** `board_mesh.z` (roll) and `board_mesh.y` (yaw) rotate cleanly toward targets. Shoe hover catching raises shoe boxes to $Y=0.18\text{m}$ during flips, locking in as griptape revolves face up.
- **Touchdown Tolerances:**
  - **Manual Catch Zone:** Landing within $\pm 15^\circ$ pitch while holding middle stick zone ($0.20 \to 0.90$) bypasses entry delays for instant, silky manual rollouts.
  - **Sideways Landing Window ($\pm 45^\circ$):** Touching down within $\pm 45^\circ$ of straight ($0^\circ/180^\circ$) snaps to orientation. Landing sideways perpendicular to travel direction ($45^\circ \to 135^\circ$ or $225^\circ \to 315^\circ$) fires a `"BAIL! (Sideways Landing / Wheel Skid)"` speed crash!
- **Simulation Speed Calibration:** Cruising max speed is calibrated to `7.0 m/s` ($\approx 15.7\text{ mph}$) with `2.0 m/s` foot pushes and `608 deg/s` flip rotation speeds for readable, floaty trick execution.

### 2. `res://scripts/input/FootInputState.gd` (Input Classification & Trick Nomenclature)
- **Stance Tracking:** Dynamically evaluates `leading_foot` and `trailing_foot` using travel velocity dot product when moving, or static SkaterController forward orientation (`-pivot.get_parent().global_transform.basis.z`) when stationary. This ensures 100% accurate switch foot recognition even when standing completely still!
- **Arc Sweep Measurement (`max_swept_angle`):** Tracks accumulated radian arc difference during pop loading (`LOADING_OLLIE`/`LOADING_NOLLIE`) to separate quarter-circle from half-circle scoops.
- **Combo Grammar:** Constructs accurate skate terminology (`Ollie`, `Nollie`, `Switch Ollie`, `Fakie Ollie`, `Varial Kickflip`, `360 Flip`, `Laser Flip`, `Mongo Push (Leading)`, `Standard Push (Trailing)`).

### 3. `res://scripts/player/SkateDeckMesh.gd` (3D Skateboard Model & Material Engine)
- Extends `Node3D` and instantiates the imported `res://skateboard.blend` asset to replace the former procedural placeholder deck.
- Applies precision scale calibration (`0.1722`) and centering offsets (`Vector3(-0.3239, -0.3585, 0.1169)`) to align directly with an 80 cm real-world deck sitting under the skater's shoes at `Y = 0.055m`.
- Features an inspector flag (`use_low_poly`) to prevent Z-fighting between overlapping high/low poly meshes from Blender, and automatically assigns high-contrast, authentic skate materials (aluminum trucks, cream polyurethane wheels, and orange bushings).
- **Two-Tone Deck (`res://resources/deck_two_tone.gdshader`):** The deck is driven by a `ShaderMaterial` rather than flat surface colors, exposing `grip_color`, `deck_bottom_color`, `bottom_emission`, `facing_sharpness`, and the `grip_grain_*` set as inspector properties.

### 3a. ⚠️ Deck Material Constraint: The Board Is One Surface
- `skateboard.blend` ships **no materials, no textures and no vertex colors** — the only material datablock is Blender's default `Dots Stroke` grease pencil, every mesh has `slots=0`, and the import uses placeholder materials (`blender/materials/export_materials=1`). All deck colour therefore lives in GDScript/shader code, **never** in the `.blend`.
- `board_high` exports 3 surfaces, but they do **not** map to grip/wood/edge. Surface 0 is the *entire* deck shell — top (area 4.98), bottom (area 5.03) and rails together — while surfaces 1-2 are hairline slivers (area 0.0098 and 0.0079) generated by stray out-of-range material indices (`28360`, `21808`) on a mesh with zero slots.
- **RULE:** Because top and bottom share one surface, they can never be separated with per-surface materials. The split is done per-fragment off the model-space normal (mesh-local **+Y is up**; the 180° Y node rotation on `board_high` leaves the up axis intact), so it rides along correctly through every flip, shuv and manual. All surfaces receive the same shader.
- The grit is deliberately faded out via `fwidth` once a noise cell drops below a pixel, so the deck reads as textured up close and as clean matte black at chase distance instead of aliasing into shimmer.

### 4. `res://scenes/player/SkaterRig.tscn` (Scene Tree & Visual Debugger)
- Contains `BoardPivot`, `BoardMesh`, truck contact raycasts, foot nodes (`LeftFoot`, `RightFoot`), and `CameraPivot`.
- Foot meshes are sized to roughly a **size US 11 M shoe** (`28.0 cm` length, `9.8 cm` width, `3.8 cm` height) with flush rounded sneaker toe tips (`ToeTip` cylinder child nodes at `X = 0.1155m`, radius `0.049m`).
- Features anatomical standing ankle poles (`PegPivot` shifted $-0.075\text{m}$ over heel articulation at `Y = 0.019m`) that stand upright vertically at rest and dynamically tilt up to $35^\circ$ during joystick deflections.
- Chase camera sits closer at `Y = 1.25m, Z = 2.1m` behind the rider tilted down $25^\circ$ for intimate trick and deck visibility.

---

## ⚠️ Critical Technical Notes & Architectural Rules
1. **Godot Euler Rotation Inversion ($\text{Y} = 180^\circ$ Compensation & Shove-it Decoupling):**
   - Because Godot uses `YXZ` Euler rotation order, turning the skateboard $180^\circ$ into Switch or Fakie flips the direction of the local X and Z axes relative to global world space.
   - **RULE:** Always apply stance sign compensation (`stance_sign = -1.0 if not left_is_front else 1.0`) when setting local X pitch targets for pops and manuals. For flip roll targets, decouple rotation from $180^\circ$ deck yaw reversals after Shove-its (`deck_orientation_comp = -1.0 if cos(deg_to_rad(board_mesh.y)) < 0.0 else 1.0`) and invert roll exclusively for Nollie pops (`-1.0`). For Shove-it and Varial spin yaw targets around Y, NEVER couple rotation to `deck_orientation_comp` or physical deck reversal; spin sign depends entirely on whether scooping off the tail (Ollie/Switch Ollie) or nose (Nollie/Fakie Ollie) relative to the skater's body. In Fakie stance, swap Kickflip/Heelflip trick labels in `FootInputState.gd` to print correct terminology while preserving control-to-rotation kinematics.
2. **Modular Speed Parameters:**
   - Always derive motion rates from top-level exported variables (`flip_speed_deg`, `spin_speed_deg`, `body_spin_speed_deg`, `max_push_speed`, `push_impulse`, `rolling_friction`). Never hardcode velocity literals inside tick equations.

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
- [x] **Two-Tone Deck for Trick Readability:** Replaced the flat griptape-coloured deck (which rendered the underside the same near-black as the top) with `deck_two_tone.gdshader`. Griptape black stays on the standing side while the underside runs high-visibility orange (`Color(0.95, 0.30, 0.02)`) so board rotation reads clearly mid-air. Includes a procedural two-octave griptape grain driven mainly by normal perturbation (near-black albedo has too little value range to carry the texture on colour alone) and a `bottom_emission` floor of `0.30`, since airborne the underside falls to ambient-only lighting and sinks to muddy brick exactly when the spin most needs reading.
- [x] **Foot Mesh Refinement & Camera Pull-In:** Sized foot meshes to US 11 M dimensions (`28 cm` long by `9.8 cm` wide, `3.8 cm` tall), adjusted heel peg articulation offsets (`-0.075m`), and pulled the chase camera closer (`Y = 1.25m, Z = 2.1m`) for improved deck and foot visibility.
- [x] **Stance Flip Direction & Shove-it Decoupling Fix:** Decoupled trick spin/flip rotation from $180^\circ$ deck yaw reversals after Shove-its in `SkaterController.gd`, inverted roll directions to correct backward Nollie and Switch flips, and corrected backwards HUD trick name labeling for Fakie kickflips/heelflips in `FootInputState.gd`.
- [x] **Varial & Shove-it Spin Direction Decoupling Fix:** Removed board orientation coupling (`deck_orientation_comp`) from `spin_sign` in `SkaterController.gd`. Unlike flip roll (Z-axis), horizontal yaw spins (Y-axis) must remain strictly independent of the wooden board's $180^\circ$ orientation, ensuring consistent clockwise/counterclockwise scoops relative to the skater when leaping off the nose versus tail.
- [x] **True Angular Sweep & Shove-it Buffer Refinement:** Upgraded Shove-it scoop detection from static stick coordinates to signed rotational sweep direction (`angle_difference`) in `FootInputState.gd` and `SkaterController.gd`. Set generous quarter-turn ($45^\circ \to 134^\circ$) and half-turn ($\ge 135^\circ$) buffer windows so starting position on the thumbstick circle no longer affects rotation accuracy.

---

## 🐛 Known Bugs
- **Active Bugs:** *None reported or observed.* All switch stance, stationary manual, and rotation direction issues validated cleanly in Godot headless testing.

---

## 🎯 Pending Feature Requests & Next Milestones
1. **Dynamic Camera Follow & Speed-Based FOV Scaling:**
   - *Goal:* Replace static follower camera with smooth spring-damper camera interpolation.
   - *Behavior:* Scale camera FOV dynamically based on rolling velocity (from ~75° at stationary rest up to ~88° at top cruising pace) to accentuate speed immersion without introducing motion sickness.
2. **Audio Feedback System (Future Phase):**
   - *Goal:* Integrate procedural skate audio sounds (polyurethane wheel roll hum on pavement, crisp maple tail crack pop impulses, griptape catch thuds, and wheel skid screeches on sideways touchdown bails).
