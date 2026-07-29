# 🌀 07b. Rotation Dynamics — the deck starts and stops spinning instantly
**Status:** 🚧 `PLANNED` | **Parent:** [07_FEEL_TUNING.md](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/features/07_FEEL_TUNING.md) | **Key file:** `res://scripts/player/SkaterController.gd` (`_impart_deck_rotation`, Layer 3 block, `_advance_flip_settle`)

---

## 🔍 The measured problem

**The deck has infinite angular acceleration at both ends of a trick.**

- `_impart_deck_rotation()` sets `flip_roll_rate` at the pop, and the very first integration step uses
  it in full. The deck goes from $0$ to $13.6^\circ/\text{frame}$ in **one frame**.
- At completion, `move_toward` clamps exactly on the target and `is_flip_in_progress` goes false. The
  deck drops from full rate to $0$ in **one frame**.

Nothing physical starts or stops rotating that way. This is the largest single contributor to tricks
reading as machine-driven rather than thrown, and it is not a tuning value — it is a missing term.

The constant rate *between* those two moments is correct and should stay: airborne there is genuinely
no torque on the deck, which the code already says.

## 🛠️ The three changes, in order of value

### 1. Spin-up ramp
A foot applies torque over its contact time, not instantaneously — roughly $30$–$50\text{ms}$, so
2–3 frames at 60 Hz. Ramp `flip_roll_rate` / `flip_yaw_rate` in over that window rather than starting
at full.

**Must preserve the ratio between axes.** Flip/scoop sync is a rate-*ratio* lock, so both axes have to
ramp by the same factor or a tre flip comes apart during the ramp. Scale a single shared factor, never
each axis separately.

### 2. Spin-down ramp
The feet absorb the catch over a few frames rather than arresting the deck instantly. This is the
same physical event the landing already models with `catch_cone_deg` — the rider stamping the deck
flat — just applied in mid-air.

### 3. Wobble (precession)
A real deck flicked at its *edge* receives angular momentum that is not aligned with a principal axis,
so it precesses — it tumbles slightly rather than spinning true like a wheel on an axle. A small
decaying oscillation on the third axis reproduces this. **This is mild real physics, not a cheat.**

Even $2$–$3^\circ$ reads very differently. Amplitude should scale with flick intensity
(`TrickSignature.flick_speed`) and decay over the flight, and it must be small enough not to disturb
the catch-cone judgement at touchdown.

### 4. Imperfect sync (optional, tiny)
Perfect axis synchronisation is machine-made by definition. A small consistent offset would read as
organic — but sync-ON is a deliberate design choice for clean-looking tricks, so this must stay
subtle enough that a tre flip still reads as landing together.

## 🔗 Interactions to check

- **Trick completion moves later**, so anything sized against rotation duration needs re-measuring.
- **`RiderBody.leg_stiffness` is sized against the deck's rotation** — the tuck must outlast it. A
  longer rotation may need a slower leg. Recorded in `RiderBody`'s own comments.
- **`_deck_clearance_demand()` is a peak-hold**, so it should absorb a changed rotation profile
  without help — but **re-measure worst-case clearance**, which currently sits at $+0.0078\text{m}$.
- **`FootRig._feet_released`** was latched (`e7cf89d`) precisely so rotation duration could vary, and
  held clearance positive from `flip_speed_deg` $600$ to $2400$. It should absorb this; confirm.
- **Free-spin handover.** `_flip_free_spinning` starts at the completion of turn 1 and the settle uses
  `_settle_target()`. A spin-down ramp must not fight the settle, which carries the deck's own angular
  rate — decide which owns the deceleration rather than having both act.
- **`flick_rate_min` is tied to `flip_speed_deg`** (a flat-ground kickflip must complete inside 38
  frames of airtime). A ramp eats into that budget; re-check that a soft flick is still landable.

## ✅ Verification

- **`curb_flip_repro` re-baselines.** Completion frames, catch errors and the flick-intensity
  thresholds (`roll_stops_before` / `roll_stops_after`) all shift. Expected; state which and why.
- The **roll-step cap** already fails a stutter, so it will catch a ramp that is applied unevenly.
- **`foot_rig`'s held case** asserts the clearance hold does not move mid-rotation — a good canary for
  the leg/rotation interaction.
- **Probes worth writing:** angular rate per frame across a whole trick (should ramp, hold flat, ramp
  down — no steps); worst-case deck clearance across the new profile; wobble amplitude against
  `catch_cone_deg` at touchdown.

## ❓ Open

- Ramp durations. $2$–$3$ frames is the physical estimate for the flick; the catch may want longer.
- Whether the wobble should also affect the *pitch* the feet clear, or be purely visual on `BoardMesh`.
  Purely visual is safer to start, but then it is authored decoration rather than physics — worth
  being honest about which one it is.
