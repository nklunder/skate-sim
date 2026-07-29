# 🌀 07b. Rotation Dynamics — the deck starts and stops spinning instantly
**Status:** ✅ `IMPLEMENTED` (items 1–3; item 4 deliberately not done) | **Parent:** [07_FEEL_TUNING.md](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/features/07_FEEL_TUNING.md) | **Key file:** `res://scripts/player/SkaterController.gd` (`_impart_deck_rotation`, Layer 3 block, `_advance_flip_settle`)

---

## ✅ What shipped

Three new functions in `SkaterController`, all under the `Angular Acceleration` export group:

| | Knob | Default | What it does |
|---|---|---|---|
| **1** | `flip_spin_up_time` | $0.05\text{s}$ (3 frames) | `_spin_up_scale()` — rate ramps $0 \to 1$ linearly from the pop |
| **2** | `flip_catch_time` / `flip_catch_floor` | $0.06\text{s}$ / $0.35$ | `_catch_scale()` — rate eases down into the target |
| **3** | `wobble_max_deg` / `wobble_cycles_per_turn` / `wobble_decay_time` | $2.5°$ / $1.5$ / $0.35\text{s}$ | `_advance_wobble()` — decaying precession on the free third axis |

**Measured rate profile** (`ramp` column in `curb_flip_repro`), as a fraction of peak per-frame step:

| trick | first frame | middle | last full frame | wobble peak → at landing |
|---|---|---|---|---|
| kickflip | $0.33$ | $1.00$ | $0.44$ | $2.04° \to 0.000°$ |
| tre flip | $0.33$ | $1.00$ | $0.49$ | $1.94° \to 0.000°$ |

$0.33$ is exactly $1/3$ — the first frame of a three-frame ramp. Before this, all three columns were
$1.00$.

### The three decisions that made it work

- **One shared scalar, never per-axis.** Sync is a rate-*ratio* lock, so `spin` multiplies both axes
  by the same number. A per-axis envelope would pull a tre flip apart during the ramp and reassemble
  it afterwards. The `tre flip, ramped in sync` case exists to catch exactly that.
- **The catch ramp is gated on `not trick.flick_held`.** Physically right — a rider still holding a
  spin is not catching it — and it is *also* what keeps the free-spin handover invisible. Without the
  gate the deck would decelerate into the completion of turn 1 and then jump back to full rate for
  the free spin, which is the one transition the suite says must not be visible. **All five held-
  rotation cases came out byte-identical** (`air 118`, `step 13.60`), which is the proof.
- **`flip_catch_floor` must be > 0.** `move_toward` with a rate decaying to zero approaches the
  target asymptotically and the trick never registers as complete. The floor guarantees arrival.

### Item 4 (imperfect sync) was NOT implemented

Deliberately. The doc calls it optional and tiny, and it is in direct tension with the `sync`
assertion that both axes stop on the same frame — which this feature has just *added* a second case
for. Sync-ON is a deliberate design choice for clean tricks; breaking it subtly should be its own
change, with its own decision about what the suite is then allowed to assert. **Still open.**

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

## ✅ Verification — as run

All five suites pass (12/12, 21/21, 17/17, 16/16, 16/16). **`curb_flip_repro` is the only suite that
moved at all** — `ground_physics`, `carve_and_push`, `foot_rig` and `pop_gesture` are byte-identical
to the commit before. Two cases were added, so it goes 19 → 21.

**Figures that moved, and why:**

| What | Before | After | Why |
|---|---|---|---|
| cone cases `flip_speed` | $486$ | $498$ | The spin-up ramp costs a **constant $8.1°$**, not a proportional amount — which is why all three cone cases moved by exactly the same figure. Ramping $1/3, 2/3, 1$ over three frames loses precisely one frame of rotation, and $486/60 = 8.1$. Errors restored to $36.3 / 52.9 / 86.1$ against the $35.7 / 56.0 / 86.4$ they held originally |
| `roll_stops_before` | $24$ | $26$ | A hard flick finishes soonest and so has least room to absorb the ~1 frame the ramp adds. The hard/lazy **gap** — which is what the pair actually pins — is untouched at 4+ frames |

**Worst-case deck clearance did not need re-measuring, and that is provable rather than lucky.**
`_deck_clearance_demand()` is a peak-hold on $\sin(\text{roll})$, so it depends on which roll angles
the deck *visits*, not on how fast it passes through them. The deck still sweeps the same total roll,
so it visits the same angles and the peak is identical. `foot_rig` coming out byte-identical —
including the held-clearance canary at its line 204 — corroborates it. `RiderBody.leg_stiffness` did
not need slowing either; the rotation is about one frame longer, not meaningfully so.

### 🔬 Falsified before being trusted

Each half of the feature was disabled in turn and the suite confirmed to fail:

| Disabled | Result |
|---|---|
| `flip_spin_up_time = 0` | first frame reports $1.00$ of peak — *"the deck starts spinning instantly"* |
| `flip_catch_time = 0` | last full frame reports $1.00$ of peak — *"the deck stops dead rather than being caught"* |
| touchdown wobble clear | four cases land with a permanent $0.25$–$0.44°$ tilt on the third axis |

> ⚠️ **A first version of the spin-down assertion was worthless and nearly shipped.** It measured the
> *last moving* roll step — but that step is a **partial**, clamped by `move_toward` as it lands
> exactly on the target, so its size is set by where the target happens to fall on the frame grid
> rather than by the deck's rate. With the catch ramp disabled it still read $0.47$ and **passed**.
> The assertion now measures the last **full** step, which reads exactly $1.00$ when the ramp is off.
> Recorded because the failure mode is invisible: the number looked plausible.

**The wobble's real risk turned out not to be the catch cone.** The cone reads roll and yaw only
(`SkaterController.gd:1401-1403`) and the clearance reads roll only, so a third-axis wobble cannot
disturb either *structurally* — not merely by being small. What it can do is **outlive the trick**:
nothing advances it once grounded, so a deck that lands mid-rotation keeps its tilt permanently. That
guard is asserted on every case rather than only the ramp ones, because a trick that finishes in the
air has already been wound down by the decay branch and cannot exercise the landing clear.

## ❓ Open

- **Ramp durations** shipped at $0.05\text{s}$ spin-up and $0.06\text{s}$ catch — the physical
  estimate, now live exports to tune by feel.

> ⚠️ **Correction to this document''s own budget claim.** It was first written here that the two ramps
> cost ~3 frames and "did not fit" the old pop, making a soft flick "an unavoidable primo" — which is
> why `jump_impulse` was raised $5.2 \to 6.0$. **Both halves of that were overstated.** Measured, the
> ramps cost ~$1.9$ frames, not $3$; and the shortfall is not a primo, because `catch_cone_deg`
> absorbs it — the deck lands *short but inside the cone* ($6.4^\circ$ at a $5.2$ pop, $11.9^\circ$ at
> $5.0$, $36.9^\circ$ at $4.6$ against $45^\circ$). The ramps would have fit at the old pop with a few
> degrees of catch error. The pop raise was therefore not strictly necessary for 07b — though it was
> wanted on its own terms at the time, and the pop has since been dialled back to $5.4$ in play.

- **The pop now sits at $5.4$** (peak $0.867\text{ m}$, $40$ frames), which is the lowest value at
  which a soft flick still completes with $0.0^\circ$ of catch error. Below it the pop is no longer
  free: it trades clean completion for catch margin, at the rates listed above.
- **The wobble is authored decoration, not physics — say so.** It writes `BoardMesh.rotation.x`,
  which nothing else reads. Feeding it into `_deck_clearance_demand()` would make it real and move
  the worst-case clearance figure; that is a separate, deliberate decision.
- **Item 4, imperfect sync** — see above. Not done, and it needs a decision about the `sync`
  assertion before it can be.
- **Held tricks fired by accident, and it was a threshold-sharing bug rather than a timing one.**
  Reported in play as "held flip tricks are too sensitive". `flick_held` reused
  `flick_min_deflection` ($0.35$) — the threshold that *fires* a flick — so any stick position
  capable of throwing the trick also counted as asking for another turn. Turn 1 completes ~27 frames
  after the pop, so a thumb following through had under half a second to clear it. Fixed with a
  dedicated `flick_hold_min_deflection` ($0.60$); all five suites stayed byte-identical, because the
  deliberate-hold cases drive $0.7$. Two new cases pin it from both sides — a thumb resting at $0.45$
  must give a single, and a deliberate hold at $0.65$ must still give a double, so the fix cannot
  simply have moved the problem.
- **Free-spin still ramps up but never ramps down**, by design: the catch ramp is gated off while the
  flick is held, and release hands to `_advance_flip_settle()` which carries the deck's own rate as
  it always did. The settle owns that deceleration; the flip block owns the other one. They can never
  both act, because they are different branches.
