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
- **Scoop & Shove-it Symmetry:** The skateboard kicks directly in the physical direction of your thumbstick scoop (scooping Left swings left, scooping Right swings right).
  - **Moderate Sweep ($35^\circ \to 80^\circ$ arc span):** Triggers a **$180^\circ$ Pop Shove-it** (or Varial Flip).
  - **Deep Scoop / Quarter-Turn Sweep ($\ge 80^\circ$ arc span):** Triggers a **$360^\circ$ Pop Shove-it** (or 360 Flip / Tre Flip, Laser Flip).
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

### 3. `res://scripts/player/SkateDeckMesh.gd` (Procedural Deck Geometry)
- Generates a custom `ArrayMesh` on launch featuring a **5-point smooth parabolic cross-section** (`[-1.0, -0.5, 0.0, 0.5, 1.0]`).
- Creates an authentic **concave pocket on top** (dipped center, raised rails via an 8mm quadratic edge curve) and a complementary **convex belly on the bottom maple wood**.

### 4. `res://scenes/player/SkaterRig.tscn` (Scene Tree & Visual Debugger)
- Contains `BoardPivot`, `BoardMesh`, truck contact raycasts, and foot nodes (`LeftFoot`, `RightFoot`).
- Features anatomical standing ankle poles (`PegPivot` shifted $-0.09\text{m}$ left over heel articulation) that stand upright vertically at rest and dynamically tilt up to $35^\circ$ during joystick deflections. Includes flush rounded sneaker toe tips (`ToeTip` cylinder child nodes).

---

## ⚠️ Critical Technical Notes & Architectural Rules
1. **Godot Euler Rotation Inversion ($\text{Y} = 180^\circ$ Compensation):**
   - Because Godot uses `YXZ` Euler rotation order, turning the skateboard $180^\circ$ into Switch or Fakie flips the direction of the local X and Z axes relative to global world space.
   - **RULE:** Always apply stance sign compensation (`stance_sign = -1.0 if not left_is_front else 1.0`) when setting local X pitch targets (for pops/manuals) or local Z roll targets (for kickflips/heelflips). Without this inversion, switch manuals will dip the wrong end of the board!
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
