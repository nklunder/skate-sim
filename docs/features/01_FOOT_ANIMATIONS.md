# 👟 01. Procedural Foot Animations (Visual Mastery & IK Prep)
**Status:** 🚧 `PLANNED` | **Priority:** `HIGHEST` | **Key File:** [res://scripts/player/FootRig.gd](file:///Users/nicholasklunder/Projects/skate-sim-v-2/scripts/player/FootRig.gd)

---

## 🎯 Executive Summary & Architectural Heritage
In Skate Sim V2, shoe boxes (currently US 11 M geometry centered at `X = -0.025m` to balance toe/heel overhang) represent our authoritative visual footwork layer. Crucially, these autonomous foot coordinates are engineered to act as the **direct Inverse Kinematics (IK) end-effectors** for our future humanoid biped character rig (see [05_FULL_CHARACTER_RIG.md](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/features/05_FULL_CHARACTER_RIG.md)). Every procedural slide, flick, scoop, and crouch implemented here directly enhances present visual immersion while simultaneously programming our future character's leg muscles!

---

## 🛠️ Detailed Technical Specifications & Mechanics

### 1. Two-Stage Procedural Flick Arcs (Kickflips & Heelflips)
Right now, during aerial flip tricks, both shoe boxes ascend straight upward like an elevator (`hover()` to $Y = 0.18\text{m}$) and hover passively until pavement touchdown. We will upgrade this into an authentic **Two-Stage Procedural Flick Sequence**:

```
[Pop Launch] ──► Stage A: Slide & Pocket Flick (0% to 35% airtime) ──► Stage B: Hover Catch Plane ──► Mid-Air Catch Stomp
```

#### Stage A: The Slide & Nose Pocket Flick (0% to 35% Jump Ascent)
- Immediately upon jump release (`_execute_pop`), while the trailing popping foot lifts straight upward off the tail into the hover plane, the **leading foot** (front shoe in Ollies, back shoe in Nollie/Fakie) physically slides forward along the griptape toward the nose tip.
- Upon reaching the nose pocket, it executes a high-speed diagonal flick extension driven by `TrickSignature.flip` and measured diagonal stick inputs (`flick_tilt_deg` / boned vs. rocketed angles):
  - **Kickflip Outward Sweep:** Shoe thrusts diagonally outward away from the rider's body plane ($+X$ or $-X$ depending on stance handedness, combined with forward $+Z$ progression) while angling the ankle toe-up by $\approx 15^\circ$.
  - **Heelflip Inward Sweep:** Shoe kicks straight inward across the heel rail in front of the rider's toes with a flat-soled horizontal thrust.
- **Timing Invariant & Flick Speed Scaling:** Stage A uses a **Hybrid Velocity Model** with a calibrated reference floor guaranteed to finish within the initial $30\% \to 45\%$ of jump ascent so shoe boxes clear the deck before griptape completes its first half-rotation. Analog stick deflection speed additively boosts flick velocity, rewarding explosive thumbstick snaps with snappy foot extensions!

#### Stage B: Hover Recovery & Catch Standby (45% to Catch)
- After reaching peak flick extension, the leading shoe smoothly retracts horizontally back over the deck into the hover plane ($Y = 0.18\text{m}$), anchoring directly above its default rest offset (`left_foot_rest` / `right_foot_rest`) in readiness for mid-air deck capture.

#### Stage A Variant: Late Flips (Direct Air-to-Pocket Thrust)
- When a flip is triggered late ($>30\%$ into jump ascent or while already hovering peacefully at $Y = 0.18\text{m}$), simply running Stage A from the start would force the shoe down through the revolving deck before sliding out.
- **Late Flip Invariant:** For late flips, **skip Stage A's initial griptape slide ($Y = 0.055\text{m}$) completely**. The shoe executes a direct high-speed diagonal thrust straight from hover height down-and-out through the corner pocket at **$1.5\times$ standard speed**, capturing the FORCEFUL physical snap characteristic of real-world late flips!

---

### 2. Shove-it Tail Scoops & Multi-Axis Synergy
When a trick signature includes horizontal yaw rotation (`sig.shuv_deg != 0`):
- **Lateral Tail Scoop:** The popping foot does not simply push down vertically and release; during the initial pop frames, it sweeps laterally across the width of the tail ($X$-axis displacement of $\pm 0.15\text{m}$) in the exact signed direction of the thumbstick scoop arc (`input_state.last_scoop_sign`).
- **Multi-Axis Trick Synergy (Tre Flips & Laser Flips):** In combined tricks like a 360 Flip (`shuv_deg = 360, flip = KICKFLIP`), both procedural animations execute concurrently without requiring custom composite animation assets: the rear foot executes a sharp lateral tail scoop while the front foot simultaneously slides forward and kicks diagonally through the nose pocket!

---

### 3. Pre-Pop Crouch & Weight Loading (`LOADING_OLLIE` / `LOADING_NOLLIE`)
- **Current Behavior:** When pulling down the pop thumbstick, the deck pitches up to $24^\circ$, but shoe boxes remain rigid at static rest offsets.
- **Target Behavior (Athletic Compression & Lateral Pre-Wind):**
  - **Tail Foot:** Firmly follows the dipping kicktail tip downward onto pavement ($Y \to 0.0\text{m}$).
  - **Directional Lateral Pop Synergy (Real-Time Tail Gliding):** When loading pop with horizontal stick deflection ($|\text{stick}.x| > 0.15$ for directional jumping), visually shift and rotate the popping foot across the tail width ($\pm 0.03\text{m}$ along local $X$). This position live-updates continuously every frame up to the moment of takeoff: as the player rolls their thumbstick across the bottom perimeter of the controller, the 3D shoe physically glides across different pockets of the tail in real-time, matching our live-calculated directional leap!
  - **Front Foot:** Compresses tightly onto the griptape plane while angling its toe upward slightly ($+5^\circ$ to $+10^\circ$ local X rotation).
  - **IK Synergy:** This compression clearly telegraphs jump energy before pop release and directly translates into deep athletic knee flexion when our Leg IK chains connect to these shoe boxes!

---

### 4. Mid-Air Catch Stomp (Physical Deck Arrest)
- **Current Behavior:** Feet remain elevated at hover height ($Y = 0.18\text{m}$) for the entire duration of aerial flight until pavement contact invokes `settle()`.
- **Target Behavior (Airborne Capture & Manual Catch Future-Proofing):**
  - On the exact frame our physics catch engine confirms griptape-up alignment within tolerance mid-flight (`_credit_achieved_rotation` or `_advance_flip_settle`), shoe boxes **snap downward from hover height onto the griptape rest pose ($Y = 0.055\text{m}$) mid-air**!
  - **Procedural Stomp Symmetry (Auto-Catch Default):** On standard Kickflips/Heelflips (where leading foot flicked), the leading foot stomps down $0.08\text{s}$ before the trailing foot. On Shuv-its, Tre Flips, and Varials (where trailing foot scooped), the trailing foot stomps down first to arrest spin. On straight Ollies/Nollies, both descend simultaneously.
  - **Manual Catch Compatibility (Zero Complexity Overhead):** `FootRig` is driven by explicit commands via `execute_catch_stomp(first_foot: FootInputState.Foot, dual_stomp: bool)`. This keeps `FootRig` completely agnostic as to whether the catch was triggered automatically by revolution completion or manually by future user thumbstick deflections!
  - This visually demonstrates the skater physically stomping and arresting deck spin with their feet before gravity delivers them down onto concrete pavement!

---

## 📐 Architectural Design Rules & Kinematic Invariants
1. **Local Frame Authority:** All foot positions and rotations MUST remain expressed in `BoardPivot` local space. Because `BoardPivot` handles Switch and Fakie $180^\circ$ yaw inversions natively, expressing flick vectors locally ensures regular and goofy stance maneuvers mirror accurately without redundant conditional math.
2. **Presentation Sovereignty (Rule #6):** As documented in `FootRig.gd` header notes, this node is strictly for presentation. No physical collision check, ground probe, or velocity calculation may ever read a foot animation position to determine gameplay success or failure. ✅ **Now enforced structurally** — stance classification consumes the shoes' rest offsets, so no live foot position is read anywhere outside `FootRig.gd`.
3. **Explicit Delta-Time Easing:** Use smooth trigonometric interpolation (sine/cosine impulse arcs) or delta-time easing curves (`lerpf` / `move_toward`) rather than fixed frame counts. This guarantees buttery-smooth footwork regardless of frame rate fluctuations or slow-motion simulation adjustments.
4. **Grounded Pipeline Protection (Step 8 Invariant):** In `SkaterController.gd` Step 8, calling `foot_rig.settle()` unconditionally on grounded frames would instantly clobber and erase our pre-pop crouch! Grounded settling MUST be guarded by pop intent: `if not foot_rig.is_pushing and not input_state.is_preparing_pop(): foot_rig.settle()`.
5. ~~**Stance Integrity & `update_stance_facts()` Guarantee:**~~ **OBSOLETE — deleted.** This rule required the leading foot never to cross behind `BoardPivot` center ($Z=0$), because `update_stance_facts()` read live foot positions. It now reads the shoes' **rest offsets**, which are constants captured from `SkaterRig.tscn` and cannot be disturbed by any animation. Flicks, scoops and slides may cross center freely; stance classification is immune. Do not reintroduce this constraint.
6. **Complete Rest Transform Tracking:** ✅ **DONE.** `FootRig._ready()` captures `position` **and** `rotation` into each foot's `Channel`, so every animation solves a displacement *from* rest and the spring always has an orientation to return to.
   - **Nose/Tail is a board attribute, not a rider one.** A landed shove-it puts the tail at the leading end without the rider moving. Any animation that targets "the nose pocket" must resolve which physical end that is via `left_foot_over` / `right_foot_over` (rest offset XOR `deck_reversed`), not by assuming $-Z$ is the nose. This matters because real decks are asymmetric in length and kick.
7. **Normalized Parameter Mapping (Feel Tuning Modularity):** To support endless real-time "feel" tuning without code modifications, all thumbstick deflections ($0.20$, $0.70$, $0.90$) and impulse percentages MUST be derived from exported top-level variables (`manual_zone_min`, `manual_zone_max`, `pop_load_threshold`, `manual_pop_ratio`). All foot compression and low-pop scaling curves must evaluate against normalized ratios across these configured boundaries rather than hardcoded literals.


---

## ✅ Resolved Design Decisions & Reference Notes
1. **Flick Speed Scaling (Hybrid Model):** We use a calibrated floor velocity (ensuring Stage A always completes within $35\%$ of jump ascent to prevent griptape intersection) combined with additive athletic scaling derived from analog thumbstick flick velocity.
2. **Late Flip Responsiveness (Direct Air-to-Pocket Thrust):** For late flips initiated while shoes are already hovering in mid-air, we bypass the initial horizontal griptape slide completely and thrust diagonally out from hover height at $1.5\times$ standard speed.
3. **Procedural Stomp & Manual Catch Support:** Catch animations expose an explicit `execute_catch_stomp(first_foot, dual_stomp)` API. This natively powers procedural stomp symmetry (front foot catches flips, back foot catches shuvs) while adding zero overhead for future tactile "Manual Catch" analog thumbstick catching!
4. **Manual Tricks & Pop-Out Symmetry (Zero Rework):** Trick inputs out of manuals (e.g., Nollie Tre Flip out of a Nose Manual) utilize the exact same thumbstick scoop and flick pipeline as flatground maneuvers. Because Pre-Pop Crouch uses Continuous Deflection Scaling, transitioning from manual balance ($0.20 \to 0.90$) into pop execution ($\ge 0.70$) operates along a fluid kinematic continuum without discrete state interruptions. Pop height out of manuals is seamlessly reduced by applying a configurable multiplier (`manual_pop_ratio = 0.75`) in `_execute_pop()`.
5. **Phase-Locked Push Cadence & Recovery Blending:** To prevent animation stutter from button spam and ensure smooth leg transitions (e.g. alternating between Standard and Mongo pushes, or interrupting a push to load a trick), grounded leg motions operate under a **Phase-Locked State Model**:
   - **Mutual Exclusion Invariant:** Both shoe boxes may never leave the deck simultaneously while grounded. When alternating between Standard and Mongo pushing, the active foot must complete its recovery phase and contact the deck before the opposite foot begins reaching.
   - **Cadence Throttling:** Button spam during an active stroke is throttled; consecutive pushes on the same foot smoothly loop from the recovery phase back into reach without settling jitter.
   - **Smooth Pop/Manual Interruption:** Attempting to load an Ollie/Nollie or enter a Manual mid-push terminates the propulsion phase and executes an accelerated recovery blend ($\approx 0.08\text{s}$) back onto the deck before takeoff, enforcing authentic physical weight recovery!
6. **Touchdown Impact Absorption (Suspension Synergy):** Touchdown foot posture derives directly from our existing `_landing_dip` variable in `SkaterController.gd`. On high impact velocity landings (drops, steep banks, or transition touchdowns), shoe boxes compress inward along local $Z$ toward center bolts and angle out slightly at the ankles—simulating deep shock-absorbing knee compression—before springing back out as `_landing_dip` relaxes over $\approx 0.20\text{s}$. No separate collision timers or drop exception tables are required.
7. **Pressure-Scaled Manual Flick-Outs & Ledge Drops (No-Pop / Low-Pop Flips):** Currently, a flip requires pulling the tail stick past $\ge 0.70$ (`LOADING_OLLIE`), ignoring flicks during gentle manual balance ($0.20 \to 0.69$). We expand the flick recognition window so any active manual balance ($0.20 \to 0.90$) permits flicking out! Instead of a binary full jump, vertical impulse in `_execute_pop()` scales dynamically with trailing thumbstick pressure: gentle manual holds ($0.20 \to 0.55$) generate a zero-to-low pop ($0\% \to 25\%$ impulse)—perfect for realistic un-popped kickflip drops off ledges and curbs—while heavy compression ($\ge 0.70$) smoothly ramps to full manual pop height ($75\%$).
8. **Flatground Ollie Compression vs Manual Sovereignty (2-Stage Balance Law):** To ensure full tail compression ($\ge 0.90$ down to $1.0$) on flat ground cleanly prepares athletic jump compression without raising the nose, manual pitch initialization operates under a 2-stage law (`was_manualing`). From standard 4-wheel riding, entering a manual requires mid-zone precision balance ($0.20 < y \le 0.90$), keeping flatground Ollie loads and tail-pocket lateral shifts cleanly flat. Once an active manual is established, balance tracking shifts to polar vector magnitude (`length() >= 0.20`), holding truck pivot tilt stable during full circular Shove-it scoops and deep pop deflections without dropping out or clashing with touchdown tolerances.



