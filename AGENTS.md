# 🤖 AGENTS.md - Skate Sim V2 Knowledgebase & AI Engineering Rules

> **IMPORTANT INSTRUCTION FOR ALL AI AGENTS:**  
> 1. **Read First:** At the beginning of any new chat session or when resuming work on this repository, you **MUST read this `AGENTS.md` file first** to synchronize your understanding of the architecture, design philosophy, and progress.  
> 2. **Archival Reference & Feature Blueprints:** For deep dives into past regressions, milestones, or technical specs, refer to:
>    - [docs/BUG_ARCHIVE.md](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/BUG_ARCHIVE.md) — Historical bug post-mortems and resolved physics regressions.
>    - [docs/CHANGELOG_LEDGER.md](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/CHANGELOG_LEDGER.md) — Chronology of completed session tasks and feature implementations.
>    - [docs/CLEANUP.md](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/CLEANUP.md) — Known debt, deferred work, and latent traps. **Read before proposing any refactor**: an item may already have a decided approach, be blocked on a user decision, or be deliberately frozen. It is not a work queue to burn down.
>    - [docs/features/](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/features) ([INDEX.md](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/features/INDEX.md)) — Feature engineering blueprints, requirements, and subsystem architectural references.
> 3. **Auto-Update Protocol:** You **MUST automatically update this file** immediately whenever:
>    - The user provides corrective feedback or refines game feel/rules.
>    - Architectural or design decisions are established (e.g., via `/grill-me` interviews).
>    - New features, trick mechanics, or physics adjustments are deployed and verified (log major feature completions to `docs/CHANGELOG_LEDGER.md`).
>    - A new known bug or feature request is identified (if a major bug is resolved, migrate its post-mortem to `docs/BUG_ARCHIVE.md`).
> 4. **Validation Routine:** Whenever scripts are edited, proactively execute headless validation using `/Applications/Godot.app/Contents/MacOS/Godot --headless --quit` before reporting completion. Then run both regression suites:
   - `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/ground_physics.tscn`
   - `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/curb_flip_repro.tscn`
   - `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/carve_and_push.tscn`
   - `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . res://tests/foot_rig.tscn`
   - **Compare the printed NUMBERS against the previous run, not just `PASS`/`FAIL`.** Several assertions check magnitudes only, so a drifted sign or a clobbered input can pass silently. A refactor should reproduce every figure exactly.
5. **Adding a new `class_name` script: run `--headless --import` FIRST.** Until you do, the global class cache does not know the type and *every* consumer fails with `Parse Error: Could not find type "X" in the current scope` — which looks like a broken refactor rather than a stale cache. Verify with `grep -c '<ClassName>' .godot/global_script_class_cache.cfg`.
6. **A parse error makes a test suite HANG, not fail.** The harness never reaches its `quit()`, so the run sits there until it is killed. If a suite stops producing output, check for `Parse Error` in the log before assuming it is slow.

---

## 🛹 Project Vision & Control Philosophy
**Skate Sim V2** is an authentic, physics-driven skateboarding simulator built in Godot 4.7 (Vulkan Forward+), designed around anatomical foot control, weighted physical responsiveness, and state-of-the-art procedural animation.

### Core Control Tenets
- **Anatomical Foot Mapping:** Analog thumbsticks correspond directly to physical feet:
  - **Left Stick = Left Foot** (Blue shoe box, mapped to Triangle/Circle for push/kick)
  - **Right Stick = Right Foot** (Red shoe box, mapped to Triangle/Circle for push/kick)
- **Universal Trick Rule:** Whether riding **Regular Forward, Switch, Nollie, or Fakie**:
  - Controls always map directly to the foot physically sitting over the active nose or tail.
  - **Flics Outward** (away from toes, behind the body plane) = **Kickflip**.
  - **Flices Inward** (toward toes, in front of the body plane) = **Heelflip**.
- **Scoop & Shove-it Symmetry:** The skateboard kicks directly in the true rotational direction of your thumbstick sweep, completely independent of starting position on the joystick or physical deck alignment.
  - **Standard Scoop Buffer ($40^\circ \to 94^\circ$ arc span):** Triggers a **$180^\circ$ Pop Shove-it** (or Varial Flip).
  - **Deep Scoop Buffer ($\ge 95^\circ$ arc span):** Triggers a **$360^\circ$ Pop Shove-it** (or 360 Flip / Tre Flip, Laser Flip), reducing required thumbstick rotational effort while avoiding accidental misfires.
- **Session-Style Pop Impulse Control (Directional Jumping):** Holding the pop thumbstick slightly off-center left or right when popping an Ollie or Nollie imparts a lateral directional leap:
  - **Deadzone & Scaling:** Horizontal stick deflection (`stick.x`) has an inner deadzone ($|x| < 0.15$) for straight gap consistency, smoothly scaling out to 100% lateral velocity (`1.5 m/s`) at $|x| = 0.70$.
  - **Travel-Relative Mapping:** Joystick Left (`stick.x < 0`) always pops to the left of your travel line, and Joystick Right (`stick.x > 0`) pops to the right, consistent across Ollie, Nollie, Switch, and Fakie.
  - **Scoop Protection:** When an arc sweep ($\ge 40^\circ$) is detected for Pop Shove-its or 360 Flips, directional lateral impulse is automatically disabled to prevent unwanted sideways launches during scooping tricks.
  - **Pressure-Scaled Manual Flick-Outs & Low-Pop Ledge Drops:** Any active manual balance ($0.20 \to 0.90$) permits initiating flicks or scoops without requiring full pop loading ($\ge 0.70$). Vertical velocity scales dynamically with trailing stick pressure via `pop_impulse_scale`: gentle manual holds ($0.20 \to 0.55$) yield a zero-to-low pop ($0\% \to 25\%$ impulse) for realistic un-popped ledge drops, while heavy compression ($\ge 0.70$) smoothly ramps to full pop impulse ($75\%$ manual pop-out). Grounded turning remains 100% untouched during gentle manual holds via `is_preparing_pop()` ($\ge 0.70$).
- **Analog Trigger Body Rotation:** L and R trigger pulls spin the skater in mid-air. An **audio-log power taper curve ($y = \text{sign}(x) \cdot |x|^{2.2}$)** desensitizes light-to-mid squeezes for subtle styling adjustments while scaling exponentially to 100% spin velocity (`554 deg/s`) for explosive flat-ground 360s!


---

## 🛠️ Key Files & System Architecture

### 1. `res://scripts/player/SkaterController.gd` (3-Layer Kinematics & Touchdown Engine)
- **Layer 1 (Body Spin Authority):** Trigger lean rotates `board_pivot.y` directly (with fluid angular momentum lerping `lerp 20.0 * delta`) so the rolling travel vector and chase camera stay anchored cleanly behind the rider. Pre-wind steering on the ground is damped by 80% during pop loading.
- **Grounded Steering & Stationary Kickturns:** Above low speeds ($\ge 0.5\text{ m/s}$), shoulder triggers carve through bushing turn rates around center origin. Below `@export var kickturn_max_speed: float = 0.5`, turning switches to a **Stationary Kickturn**:
  - **Axle Anchoring:** In low-speed turns, `global_position` dynamically translates by the pre/post-rotation delta of the trailing rear contact axle (`manual_axle_z`), locking back wheel tires to their exact pavement coordinate while the nose swings in an arc.
  - **Rule — the kickturn anchor is `pivot_z_to_rig(trailing_axle_z())`.** The axle is a `BoardPivot` fact and the rotation happens in the rig's frame, so it must be converted (critical rule 1). Omitting the conversion inverted the anchor for **all** of switch/fakie and pivoted the board on its airborne truck — see BUG_ARCHIVE #6.
  - **Carve Latching (`_is_carve_latched`):** Turns initiated above $0.5\text{ m/s}$ remain in continuous carving mode as friction decelerates the board down to a near-stall ($< 0.05\text{ m/s}$), preventing sudden mid-carve kickturn interruptions.
  - **Steering rate is `lean × turn_speed × _lean_authority()`.** `_lean_authority()` is the single home for "how much of the rider's weight is available to lean the deck with" — carving works by leaning onto the bushings, so every body state that takes weight off a truck registers there as a named contributor rather than bolting another multiplier onto the turn rate. Currently: pop loading (`pop_load_turn_damping = 0.2`, weight shifted onto the tail) and pushing (`push_turn_damping = 0.15`, a foot on the ground, easing back over `push_stroke_time`). **Grinds and manuals belong here too.** Most restrictive contributor governs, since these are alternative body positions rather than stacking ones.
  - **Rule — damp STEERING, never the impulse.** Gating a gameplay term on a body state is fine; gating it on an *animation* is not. `_since_push` is a physics timer, deliberately independent of `FootRig.push_anim_duration`.
  - **Kickturn Pitch Lift & Manual Protection:** Automatically applies `@export var kickturn_pitch_deg: float = 10.0` nose lift during slow turns (bypassing `manual_entry_delay` for instant elevation) **only** when neither thumbstick is holding an active manual or nose manual. When balancing a manual (`is_manualing == true`), user pitch controls remain completely untouched while turns cleanly rotate around the active grounded axle!
- **Layer 2 (Airborne & Grounded Pitch Control):** Thumbsticks tilt the nose/tail between `0.20 to 0.90` stick deflection for manuals ($24^\circ$ tilt) and airborne realignments. Flick tilt dynamically targets measured diagonal angles ("boned" downward up to $-18^\circ$, "rocketed" upward up to $+18^\circ$).
  - **Dynamic Pop Leveling & Non-Linear Velocity Easing:** Initial pop pitch scales with takeoff vertical impulse (`_takeoff_vertical_velocity`), producing steep angles ($50^\circ$ at full pop). Mid-air leveling evaluates ascending momentum against takeoff velocity passed through an exponential power curve (`pow(clamp(vertical_velocity / _takeoff_vertical_velocity, 0.0, 1.0), pop_leveling_exponent)` with default exponent `2.5`). This simulates the front foot scraping up the deck to rapidly level off initial explosive pop tilt during early ascent, gliding horizontally through jump apex (`vertical_velocity == 0.0`).
- **Layer 3 (Deck Flip & Spin Authority & Gyroscopic Coupling):** `board_mesh.z` (roll) and `board_mesh.y` (yaw) rotate toward targets. When combining roll and yaw simultaneously (e.g., Varial Flips or 360 Flips), multi-axis inertial coupling (`rotational_complexity_coupling = 0.15`) applies physical completion drag proportionally scaled by total sweep density. Simple tricks (Ollies/Kickflips/180s) complete and trigger procedural mid-air catch stomps cleanly at apex ($\approx 0.35\text{s}$, frame 21), Varial Flips catch during early descent ($\approx 0.43\text{s}$, frame 26), and 360 Flips complete deeper into descent ($\approx 0.45\text{s}$, frame 27). Both shoe coordinates firmly snap back to deck rest pose upon touchdown and maintain locked standing posture during grounded rolling whenever not pushing.
- **Touchdown Tolerances:**
  - **Manual Catch Zone:** Landing within $\pm 15^\circ$ pitch while the rider is still asking for that end down bypasses entry delays for instant manual rollouts.
  - **Rule — the TWO-STAGE BALANCE LAW lives only on `TrickState`.** `enters_tail_balance()` / `enters_nose_balance()` (stage 1: from four wheels, needs mid-zone precision **and** no active scoop) and `holds_tail_balance()` / `holds_nose_balance()` (stage 2: already balancing, switches to polar magnitude during a pop load). Grounded pitch and touchdown classification both call these — they previously wrote the same compound expression out twice, one edit away from disagreeing about what a manual is. That expression is the fix for BUG_ARCHIVE #5 and is not self-evident; never inline it.
  - **Sideways Landing Window ($\pm 45^\circ$):** Touching down within $\pm 45^\circ$ of straight ($0^\circ/180^\circ$) snaps to orientation. Landing sideways perpendicular to travel direction fires a `"BAIL! (Sideways Landing / Wheel Skid)"` speed crash!
- **Simulation Speed Calibration:** Cruising max speed is calibrated to `7.0 m/s` ($\approx 15.7\text{ mph}$) with `2.0 m/s` foot pushes, `1020 deg/s` ($17^\circ/\text{frame}$) flip rotation speeds, and `540 deg/s` ($9^\circ/\text{frame}$) spin speeds so single-axis flip tricks finish right around jump apex ($\approx 0.35\text{s}$).

### 1a. 🎬 Frame Pipeline & Extracted Nodes
- **`SkaterController._physics_process()` is an ORDERED PIPELINE, not a bag of updates.** Each numbered step is a named method (`_update_grounded_state()`, `_apply_push_inputs()`, `_execute_pop()`, `_integrate_flight()`, `_integrate_position()`, …). Reordering the calls is a behaviour change even though no method body changes.
- **Rule — Presentation nodes are driven by explicit calls, never their own `_physics_process`:** `ChaseCamera.follow(delta)` and `FootRig.solve(delta, frame, …)` are invoked from the pipeline so their ordering is visible in code. A self-driven `_physics_process` would make it a property of node order in `SkaterRig.tscn` — invisible, and a one-frame lag the moment anyone reorders the tree.
- **`res://scripts/player/ChaseCamera.gd`** (on `CameraPivot`): owns all camera framing (`camera_follow_speed`, `camera_max_swing_deg`, `camera_side_offset_deg/_m`, `camera_position_damp`). MUST run after step 7 integrates position, or it frames where the skater *was*.
- **`res://scripts/player/FootRig.gd`** (under `BoardPivot`): shoe boxes, ankle pegs, and every animation that moves them. **Presentation only, and now structurally so** — nothing outside the file reads a live foot position, so an animation may put a shoe anywhere at all.
  - **Rule — feet are posed at ONE point in the pipeline (step 8c), never several.** Posing was once spread across three call sites; "which animation wins" then had to be reconstructed from their order. `FootRig` now arbitrates internally, in `_advance_states()`, read top-to-bottom as a priority list.
  - **Rule — states are PER FOOT.** A tre flip scoops with the trailing foot while the leading foot flicks; one shared state cannot express that. Includes the mid-air catch via the `STOMPING` state, which is entered by `_advance_states()` when the deck stops turning - not by an external call. `execute_catch_stomp()` is gone: the tuck arc below already delivers the foot to the deck, so there was nothing left for a discrete catch event to do.
  - **Rule — every state solves a TARGET from the rest pose; a damped spring carries the shoe there.** Never write `foot.position` directly. Weight and settle emerge from the integration, and an interrupted animation is safe by construction — the target changes and existing velocity carries through. `settle_now()` is the one deliberate exception (touchdown is an event, not a blend). The spring now carries the ANIMATION pose only — `Channel.pose_position`, deliberately not the node's transform — and the rider's leg is added on top rigidly.
  - **Rule — the feet are the end of the RIDER'S LEGS, and `foot_lift` is applied RIGIDLY.** `RiderBody` owns a leg length with a spring, a tuck limit, and a contact clamp; `FootRig` composes `node.position = sprung_animation_pose + foot_lift`. The leg is *not* sprung a second time — springing the shoe toward its own leg length double-filtered the motion and cost 16 mm of deck clearance in the first frames of a flip, while the deck was turning fastest. A foot is the end of a leg; it does not chase it.
  - **Rule — THE OLLIE RULE: the feet only leave the deck when the deck needs the room.** A plain ollie — no flip, no shuv — keeps the shoes in contact for the whole jump. In a real ollie the board is dragged up *by* the front foot, so tucking the knees raises the rider's **hips** while the feet stay planted and the deck rises with them; feet release only to let the deck turn over underneath. The leg's tuck therefore reaches the shoes only while `deck_is_spinning`. This is why `leg_stiffness` is sized against the **rotation** and not against airtime: the tuck must outlast the deck turning, *and* be spent by the time it stops, because that is the instant the feet take the deck back — a tuck still standing then would be a step change in foot height.
  - **Rule — the deck's own silhouette is a FLOOR under the feet (`Frame.deck_reach`).** `deck_half_width * |sin(roll)|` is how far a rolling deck reaches above its long axis; the shoes are held above it times `deck_clearance_margin`. Taking the greater of leg-tuck and floor is what makes this one motion rather than two — the leg is above the floor for most of a flip, so what you see is a single tuck, and the floor only takes over at the end where the leg has spent itself but the deck is still coming round, carrying the feet to exactly zero as it arrives flat. It makes intersection impossible **by construction** rather than by tuning (measured worst-case clearance went from −16 mm, through −0.6 mm for a hand-authored parabola, to **+3.8 mm**). It cannot disturb an ollie: reach is zero at zero roll.
  - **Rule — leg damping is sized against AIRTIME, not picked for feel.** The tuck must outlast the deck's rotation or the feet come home while the board is still turning and it clips through them. `leg_damping_ratio = 0.3` is well under 1.0 deliberately: it makes a broad hump that HOLDS the feet clear rather than a spike that decays. Overshoot past standing is invisible because `foot_lift()` floors at zero, so a ringing leg cannot push a foot through the deck.
  - **Rule — the spring pair is chosen PER STATE, and the stomp is the one that is an IMPACT.** Every pose settles at `foot_stiffness`/`foot_damping_ratio` (400, critically damped, ~$0.20\text{s}$) except `STOMPING`, which integrates at `stomp_stiffness`/`stomp_damping_ratio` (1600, $0.60$, ~$0.10\text{s}$). Critical damping is *by definition* the fastest arrival **that does not overshoot** — so running the catch on it made the feet decelerate into the deck and never quite arrive (still $1$–$2\text{cm}$ short at touchdown, then snapped flat by `settle_now()`). That asymptote-then-teleport is what reads as the shoes being *sucked* onto the board rather than landing on it. **Tune the damping against the DISCRETE integrator:** semi-implicit Euler adds numerical damping, so at $k=1600$, $dt=1/60$ both $0.70$ and $0.65$ ring by exactly zero, $0.60$ gives $2.1\text{mm}$ and $0.55$ gives $7.1\text{mm}$. The useful band is narrow and nowhere near where the analytic formula puts it — re-measure if stiffness or the physics tick changes.
  - Rest pose (position **and** rotation) is captured from `SkaterRig.tscn` in `_ready()`. Never hardcode foot offsets in script.
- **`travel_min_speed` lives on `SkaterController`, not the camera:** both the camera's heading and `_travel_axis_sign` ask "is travel readable yet?", and they must not be able to disagree.

### 2. Input: `RiderInput.gd` → `TrickState.gd` (two nodes, deliberately)
- **The chain is `StickPoller` → `RiderInput` → `TrickState`, each layer knowing strictly less about the hardware than the last.** The old `FootInputState` was all three at once — an input reader, a trick state machine, and a scratchpad `SkaterController` wrote back into from six places.
  - **`res://scripts/input/RiderInput.gd`** — what the rider is doing with the controller and where their feet are on the board: stick vectors, magnitudes, latched buttons, stance facts. **Knows nothing about tricks.**
  - **`res://scripts/tricks/TrickState.gd`** — what those gestures add up to: pop loading, scoop arc measurement, flick classification, the `TrickSignature`.
- **Rule — `TrickState` is a CHILD of `RiderInput`, not a sibling.** Godot runs `_physics_process` in tree order, parents first, so the child arrangement is what guarantees the gesture recogniser reads a fully-updated stick rather than a half-updated one. Do not flatten them.
- **Rule — the stick that FIRES a pop is SPENT until it returns to neutral (`TrickState.pop_load_spent`).** A rider pops by flicking the *opposite* stick, so the loading stick is still buried at takeoff. Airborne pitch read that as a live request and held the deck ~$24^\circ$ nose-up for the entire flight, landing them in a manual they never asked for instead of levelling through apex. Airborne pitch therefore reads `airborne_front_stick()` / `airborne_back_stick()`, which report a spent stick as centred; releasing and re-applying still steers pitch in the air. **Airborne only** — grounded pitch and the touchdown manual catch keep reading `RiderInput` directly, so holding through a landing still enters a manual under the two-stage balance law exactly as before.
- **Rule — deflection thresholds are exported, never literals.** `manual_zone_min`, `pop_load_threshold`, `low_pop_knee`, `low_pop_max_ratio`, `flick_min_deflection`, `flick_release_band`, `scoop_min_deflection`, `lateral_pop_deadzone`, `lateral_pop_full` all live on `TrickState`. The lateral-pop lockout keys off `shuv_180_threshold_deg` **itself** rather than a copy of its value, so retuning the shuv threshold cannot silently desynchronise the two.

- **Device polling is isolated in `res://scripts/input/StickPoller.gd`:** the only code that knows a gamepad exists. It returns a `Sample`; everything downstream works from that, which is why the regression suites can drive the controller by writing stick vectors instead of simulating a joypad.
- **Rule — the poller reports SELECTIONS, not sticky state:** `Sample.camera_side_select` is `0` when the d-pad is idle, and `camera_side` is only assigned on a non-zero. Reporting the live side instead made the poller overwrite `camera_side` every frame, clobbering any value set from outside the device layer.
- **Debug-only strings stay out of the input tick:** joypad button labels live in `res://scripts/ui/JoyButtonNames.gd` and are polled by `DebugHUD`, not by `_poll_inputs()`.
- **Stance Tracking:** Dynamically evaluates `leading_foot` and `trailing_foot` using travel velocity dot product when moving, or the **`SkaterRoot` forward vector passed in as `root`** when stationary. Ensures accurate switch foot recognition even when standing still.
- **Rule — Stance is derived from the shoes' REST OFFSETS, never their live positions.** `leading_foot` drives pop classification, every pitch sign, `front_stick()`/`back_stick()`, push type and the kickturn axle. Reading live foot nodes coupled all of that to a presentation-only node, and forced every foot animation to honour a hand-maintained "never cross `Z = 0`" invariant. Rests are constants from `SkaterRig.tscn`, so animations are now free.
- **Rule — NOSE/TAIL is a property of the BOARD; LEADING/TRAILING is a property of the RIDER. They are different questions and take different inputs:**
  - Land a shove-it and the deck has turned 180° under a rider who has not moved — the tail is now at the leading end while `leading_foot` is unchanged.
  - `left_foot_over` / `right_foot_over` = (which deck end the shoe is mounted over, from rests) **XOR** (`deck_reversed`, read off `board_mesh.rotation_degrees.y`). Never measure it against `BoardPivot`'s −Z, which is the *rider's* forward, not the board's nose.
  - This exists because real decks are asymmetric: nose and tail differ in length and kick, so anything drawing or measuring against that geometry must know which one it is on.
  - **Corollary — foot animation is authored in the RIDER frame.** Which foot pops, which flicks, and which way each travels come from `leading_foot`/`trailing_foot`; nose/tail is consulted *only* to ask how much deck exists at that edge. The pop taxonomy already works this way — `OLLIE`/`SWITCH_OLLIE` means the trailing stick loaded, `NOLLIE`/`FAKIE_OLLIE` the leading stick — so it never touches board geometry. Rule: *the flicking foot always travels toward the edge opposite the popping foot.*
- **Foot Identity is an `enum`, not a String:** Use `Foot { LEFT, RIGHT }` and `DeckEnd { NOSE, TAIL }`. Compare enum values; convert to text **only** at the HUD boundary via `foot_name()` / `deck_end_name()`.
- **`front_stick()` / `back_stick()`:** Return the leading / trailing foot's stick. Always invoke these rather than re-deriving stance handedness inline.
- **Arc Sweep Measurement (`max_swept_angle`):** Accumulates frame-to-frame `angle_difference` deltas **in degrees** (`_accumulated_scoop_deg`) during pop loading (`LOADING_OLLIE`/`LOADING_NOLLIE`) to prevent wrap-around bugs when sweeps exceed $180^\circ$.
- **Trick Measurement:** `_build_trick_signature()` populates `current_trick` (a `TrickSignature`) with pop / flip / shuv. It builds **no display strings** — naming happens at touchdown in `SkaterController._finalise_trick_name()`.

### 2a. 🏷️ Trick Naming (`res://scripts/tricks/`)
- **`TrickSignature.gd` & `TrickNames.gd`:** Measured physical action (`pop`, `flip`, `shuv_deg`, `body_deg`) is compared against `TABLE` in `TrickNames.gd` (the **only file to edit to add or rename a trick**).
- **Core Principle:** The engine encodes **no skateboarding naming conventions**. It measures the physical action; the table assigns the name.
- **Rule — Count spin in `world`, not `shuv`, when authoring rows:** `shuv` is board rotation *relative to the body*; `board_world` (= shuv + body) is total board turn. A **Bigflip** is `shuv = -180, body = -180` (world -360), **not** `shuv = -360`.
- **Rule — Unlisted fields must be inert:** In a table rule, any omitted field among `flip` / `shuv` / `body` **must be zero** to match. Use `ANY` to explicitly ignore a field.
- **Rule — Rotations are measured in DIFFERENT FRAMES:** Both conversions live in `TrickSignature.gd` and nowhere else:
  - `shuv_deg`: Measured in thumbstick sweep (rider-relative). Converter: `shuv_sign(is_goofy, left_foot_scoops)`.
  - `body_deg`: Measured in world yaw of `board_pivot`. Converter: `body_sign(is_goofy, riding_reversed)`.
- **Rule — Naming happens at touchdown, never at pop:** Body rotation accrues mid-air (`airborne_body_yaw_deg`). Tricks defined by body rotation (bigflip, frontside flip) cannot be named until touchdown.

### 2b. 🧱 Surface Collision (`res://scripts/physics/SurfaceProbe.gd` & `SurfaceAlign`)
- **`SurfaceProbe.gd`:** Pure space state geometry queries against static collision (`cast_down`, `highest_below`, `cast_horizontal`, `find_edge_near`). Uses explicit world-space rays (from `SkaterRoot`'s yaw-only basis) rather than tilted `RayCast3D` child nodes.
- **Rule — Surface Tilt Lives on its Own Node (`SurfaceAlign`):** The rig hierarchy is `SkaterRoot → SurfaceAlign → BoardPivot → BoardMesh`. `SurfaceAlign` carries **only** surface pitch/roll. Never merge it into `BoardPivot.rotation_degrees.x` (trick pitch) or `BoardMesh.rotation_degrees.z` (flip roll).
- **Ride Height (`ride_height = 0.078`):** Measured distance from rig origin to lowest wheel vertex. **Never hardcode ground heights** or assume flat terrain at `y = 0`.
- **Rule — Assert Surface Alignment as Up Axis == Normal:** Target rotation solves to local $+Y$ onto probed normal: `target.x = atan2(n.z, n.y)` and `target.z = atan2(-n.x, n.y)`. Getting negations wrong tilts away from slopes by 2x.
- **Rule — Manuals Pivot on Contact Axle:** Grounded manuals offset `board_pivot.position` to pivot at axle center (`z = ±0.225`, `y = -(ride_height - wheel_radius)`) so dipping ends don't penetrate floor geometry. Airborne decks must pitch about their center.
- **Rule — Only Touchdown Path May Ground the Skater:** Proximity checks may keep `is_grounded` true but never flip it false $\to$ true. Grounding belongs exclusively to touchdown branches that zero vertical velocity and call `_evaluate_touchdown_landing()`.

### 3. `res://scripts/player/SkateDeckMesh.gd` & Deck Shaders
- Extends `Node3D` and preloads standalone asset `res://assets/models/decks/skateboard.glb`.
- Applies precision scale calibration (`0.1722`) and centering offsets (`Vector3(-0.3239, -0.3585, 0.1169)`) to match an 80 cm real-world deck seated beneath shoes at `Y = 0.0155m`.
- **LOD Tiers & Shader:** Low tier (`use_low_poly = true`, default `8,328` tris) synthesizes tangents on import. Both top and bottom share a single mesh surface; color split (griptape top vs high-vis orange underside `Color(0.95, 0.30, 0.02)`) is executed per-fragment off model-space normals in `deck_two_tone.gdshader`.

### 4. `res://scenes/player/SkaterRig.tscn` & `ShoeMesh.gd` (Scene Tree & 3D Foot Assets)
- Contains `BoardPivot`, `BoardMesh`, truck contact raycasts, foot nodes (`LeftFoot`, `RightFoot`), the `FootRig` driver node, and `CameraPivot` (which carries `ChaseCamera.gd`).
- **3D Foot Assets (`ShoeMesh.gd`):** `LeftFoot` and `RightFoot` are `Node3D` containers driven by `ShoeMesh.gd`, dynamically instantiating `res://assets/models/shoes/shoes_dc_tonik_right.glb` seated at `X = -0.025m` to balance toe/heel overhang. Rest offsets sit on the **axle line** (`Z = \pm 0.225`, matching `manual_axle_z`), i.e. the rider stands over the bolts. Setup shifts toward the leading/trailing edge are animated from there, never re-authored here. Automatic scale mirroring (`is_left_shoe = true`) matches left and right shoe silhouettes, while diagnostic albedo tinting preserves testing telemetry (Blue tint for Left Foot / Triangle push, Red tint for Right Foot / Circle push).
- **Rule:** `left_foot_rest` / `right_foot_rest` are captured from this scene in `FootRig._ready()`. Never re-hardcode foot rest offsets in script.
- **Shadow Tuning:** `DirectionalLight3D` runs tuned biases (`shadow_bias = 0.02`, `shadow_normal_bias = 0.1`, `directional_shadow_max_distance = 25.0`) to prevent peter-panning at centimeter scale. `AnklePeg` meshes have `cast_shadow = 0` (OFF).

---

## ⚠️ Critical Technical Notes & Architectural Rules

1. **🧭 RIG FRAMES — never hand-roll an orientation sign. Use the conversion layer.**
   - The rig has four frames. `SkaterRoot` carries the world heading, and **two sibling chains** hang beneath it — the rider and the board — because they are two bodies, not one. **Every** conversion between them lives in the `RIG FRAMES` block in `SkaterController.gd` and nowhere else:

     | frame | adds | consumed by |
     |---|---|---|
     | `SkaterRoot` | world heading + landing residuals | `_board_axis`, steering, camera, position |
     | `RiderTorso` | the **rider's** yaw — shoulders, body spin | `pivot_reversed()`, i.e. switch/fakie |
     | `BoardPivot` | the **board's** yaw + manual pitch | trick pitch, manuals, feet, stance facts |
     | `BoardMesh` | the deck's own flip roll + shuv yaw | roll targets, nose/tail identity |

   - **Rule — `RiderTorso` and `BoardPivot` are SIBLINGS, and the feet stay under `BoardPivot`.** Keeping the feet in the deck's frame is what makes switch/fakie mirroring *inherited* rather than compensated for; only the torso separates. That is also the anatomy — feet on the board, shoulders free, twist in between. `BoardPivot`'s yaw previously carried the rider's 0/180 switch flip **and** their accumulated body spin with no way to tell them apart, which is why a boardslide (deck across the direction of travel, rider still facing near-forward) was not expressible: the rider *was* the board.
   - **Rule — being switch is a fact about the RIDER, so `pivot_reversed()` reads `RiderTorso`.** It means the person's body faces the opposite way down the line they are travelling. It read `BoardPivot` only because the rider had no frame of their own. The two coincide while the coupling is rigid and stop coinciding the moment a slide turns the deck across the rider. **Anything constructing a landed body-180 must set BOTH frames** — setting only the board describes a deck spun underneath a motionless rider, which is a boardslide, not switch stance.

   - **The API:** `leading_axle_z()` / `trailing_axle_z()` (BoardPivot-local Z of each end), `stance_sign()` (rider-relative pitch → local X), `rider_pitch_deg()` (the inverse read-back), `pivot_reversed()`, `pivot_z_to_rig()`, `deck_reversed()`, `flip_roll_sign()`.
   - **Rule — solve RIDER-relative, convert once at the assignment.** Write pitch logic as "positive means trailing-end-down" and multiply by `stance_sign()` in the single line that writes `board_pivot.rotation_degrees.x`. Never branch on `left_is_front` inline.
   - **Rule — the two facts below are NOT interchangeable.** Confusing them is exactly what caused BUG_ARCHIVE #6:
     - `leading_axle_z()` — **where the rider is going.** Flips when you roll backwards down a bank, with the board never moving.
     - `pivot_reversed()` — **how two frames relate.** Flips when you land a $180^\circ$, with your travel never changing.
   - **Rule — anything derived from BoardPivot facts but applied through `SkaterRoot`** (`rotate_y`, `to_global`, `global_position`) **must pass through `pivot_z_to_rig()`.**
   - **Rule — Shove-it / Varial yaw spins take NO deck-reversal term.** Spin sign is the raw thumbstick sweep (`input_state.last_scoop_sign`). Only flip ROLL uses `flip_roll_sign()`.
   - **Rule — mirror once.** Nollie/Fakie flip mirroring is applied in `FootInputState._build_trick_signature()` only; applying it again at the roll target cancels it out.
   - *Background: Godot uses `YXZ` Euler order, so a $180^\circ$ turn into Switch or Fakie flips local X and Z relative to world space. This layer is the same medicine `TrickSignature.gd` applies to the rotation-**naming** frames — whose conversions are the only sign logic in this project that has never regressed.*
2. **Modular Speed Parameters:**
   - Derive motion rates from exported top-level variables (`flip_speed_deg`, `spin_speed_deg`, `body_spin_speed_deg`, `max_push_speed`, `push_impulse`, `rolling_friction`, `peg_tilt_deg`). Never hardcode velocity literals in tick equations.
3. **Never Read a Display String to Drive Behavior:**
   - Trick physics must key off `input_state.current_trick` (`sig.pop == …`, `absi(sig.shuv_deg) == 360`), never off HUD strings like `last_combo_string` or `last_pop_type` (which are strictly display-only).
4. **Screen-Space Debug Visualizers vs. `BoardPivot` Yaw:**
   - `CameraPivot` is parented to `SkaterRoot`, not `BoardPivot`. To prevent visualizer mirroring in switch, resolve stick vectors onto pivot local axes via camera-relative angle (`angle_difference(camera_pivot.rotation.y, board_pivot.rotation.y)`).
5. **`velocity` is the Authoritative Motion State:**
   - `velocity` is an authoritative 3D world vector. `current_speed`, `vertical_velocity`, and `lateral_speed` are **read-only computed properties**. Never cache scalar speeds or rebuild velocity from rig facing.
   - Pushes drive along the **rolling axis**, never travel direction—allowing wheel grip to scrub lateral drift and straighten crooked rolling. Rolling sign (`_travel_axis_sign`) is preserved when speed drops to zero.
   - Grounded `velocity.y` is pinned to zero (height belongs exclusively to surface snap); airborne `velocity.y` is ballistic vertical speed.
   - Landing residuals transfer directly to rig yaw; wheel grip anisotropy (`wheel_side_grip`) governs drift scrubbing, speed penalties, wash-out bails, and carve friction simultaneously.
   - **Rule — the landing residual is a BUDGET that only ever shrinks, never a state flag.** `_landing_residual` is armed once in `_evaluate_touchdown_landing()` with the sideways speed actually arrived with, drains at `speed * landing_turn_rate_deg`, and grip removes everything *above* it at full strength. **It must have exactly one writer.** It was previously a boolean latch cleared when live lateral fell below a threshold — but steering *generates* lateral faster than the capped grip removed it, so holding a trigger through a landing kept the cap alive forever and slid the board sideways (BUG_ARCHIVE #7). Any quantity whose decay condition the player can top up is a feedback loop waiting to happen.
   - **Rule — the residual budget has a DOMAIN, bounded by `max_realign_angle_deg` ($45^\circ$).** The budget paces a *heading error* being rotated into line, and it works by the small-angle relation $v_{lat} \approx \text{speed} \times \text{angle}$, which needs an along-axis component to rotate *toward*. Land with little or no forward speed — a standing directional pop leaps purely sideways — and the angle is ~$90^\circ$, the approximation is meaningless, and draining at `speed * angular_rate` rotates nothing. It just decays speed linearly over ~$1\text{s}$ while `wheel_side_grip` (which would stop it in $28\text{ms}$) **never engages at all**, because lateral never rises above the budget. The board glided sideways like ice. Arming is therefore capped at `land_along * tan(max_realign_angle_deg)`: beyond $45^\circ$ more of the motion is across the wheels than along them, which is a skid for grip to fight, not a heading to swing. Expressed as an ANGLE, not a speed, so it scales with arrival speed. Note the low `dir` step this case used to show in `ground_physics` was **not** smoothness — travel was turning at $3.7^\circ/\text{s}$ against an intended $60$, i.e. barely moving because nothing was happening.
6. **Camera Framing Invariant:**
   - Boom offset lives on `Camera3D`; `CameraPivot` orbits rig origin. Rotating the pivot walks the camera **around** the skater while facing them.
   - Camera position and aim MUST derive from the same smoothed yaw so skaters never fall outside the FOV during sharp landing alignments.
7. **Camera Chases TRAVEL, Not Board Heading:**
   - Camera tracks direction of travel, ensuring fakie rollbacks and slope gravity reversals behave naturally without camera snaps.
   - **Rule — the travel heading is read ALONG THE WHEELS, never off total speed.** `_travel_heading` updates only while the *along-rolling-axis* component of velocity clears `travel_min_speed`. A heading is where the rider is being **carried**; sideways motion translates a rider whose heading has not changed. A standing directional pop leaps bodily sideways at up to $1.5\text{ m/s}$ — comfortably past `travel_min_speed` ($0.6$) — so read off total speed it swung the camera a full $90^\circ$ mid-flight and then **parked it there**, since travel stops on landing and the last heading is held. The rider was left filmed from the side having never turned. Total speed cannot distinguish that from real travel; the along-axis component can, and it costs the bank reversal nothing, because gravity reverses travel *along* the axis — exactly the component tested.
   - Side view uses two distinct offsets: positional `camera_side_offset_m` (`0.26m` to center vanishing point) and orbital `camera_side_offset_deg` (`2.5^\circ` to unambiguously guide reversal swings). Smooth selection (`_camera_side_smooth`), not separate offsets.
8. **Camera Slew Rates & Touchdown Alignment:**
   - Use separate rates for continuous tracking (`camera_follow_speed`) versus discontinuous reversal goals (`camera_max_swing_deg`).
   - For touchdown realignment, cap **angular rate** (`landing_turn_rate_deg`), never lateral force, ensuring world and view turn in lockstep ($60^\circ/\text{s}$ default).
9. **Never Let an Animation's Duration Decide a Physical Outcome:**
   - Judge outcomes and landability purely on state against geometry: `catch_cone_deg = min(atan(grip_friction), rail-strike angle)`, with extents measured via `SkateDeckMesh.deck_extents()`. Never read airtime, frame counts, or timer duration to gate trick success.
   - Scale multiple rotation axes onto one shared duration in `_impart_deck_rotation()` so roll and yaw retire on the exact same frame.
   - Never teleport decks flat at touchdown; integrate existing angular velocity via `_advance_flip_settle()` the short way round.

---

## 🐛 Active Bug Log & Margin Constraints

> **Historical Bug Post-Mortems:** For details on solved issues (curb flip timers, desynchronized axes, HUD slide latches), see [docs/BUG_ARCHIVE.md](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/BUG_ARCHIVE.md).

- ⚠️ **Rotation stops dead at catch without deceleration:** Airborne deck rotation axes halt immediately upon reaching targets without ease-out deceleration. Mathematically correct for foot arrest, but left open as an adjustable game-feel refinement.
- ⚠️ **Ollie-to-manual Platform margin (`2 mm`):** Pop apex is `0.8022 m` against the `0.8 m` raised platform in `TestWorld.tscn`. Any downward tweak to `jump_impulse` or upward tweak to `gravity_accel` will make the platform unreachable and present as a regression.


---

## 🎯 Pending Feature Requests & Next Milestones

> **Completed Milestone Ledger:** For the comprehensive log of completed tasks and feature implementations, see [docs/CHANGELOG_LEDGER.md](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/CHANGELOG_LEDGER.md).

0. **Transition Skating (Quarter Pipes, Bowls, Vert):**
   - *Goal:* Ride transition surfaces cleanly.
   - *Active Blocker:* `max_surface_angle_deg = 50.0`. Currently, `_probe_surface()` discards hits steeper than 50° and `_blocked_by_wall()` treats them as physical walls. Transition skating requires rethinking this threshold and global "up" assumptions; the underlying authoritative velocity vector model is already fully prepared for vertical and inverted travel.
1. **Dynamic Camera Follow & Speed-Based FOV Scaling:**
   - *Goal:* Replace static follower camera with smooth spring-damper interpolation and speed-scaled FOV (~75° at rest up to ~88° at top speed) to accentuate speed immersion.
2. **Procedural Audio Feedback System:**
   - *Goal:* Integrate procedural sound audio (polyurethane pavement hum, crisp maple tail crack pop impulses, griptape catch thuds, and sideways skid screeches).
