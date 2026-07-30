# 🎚️ 07d. Control Continuity — curves in the wrong layer, and rotations that start from zero
**Status:** ✅ `IMPLEMENTED` (items 1–2; items 3–6 are findings, deliberately not done) | **Parent:** [07_FEEL_TUNING.md](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/features/07_FEEL_TUNING.md) | **Key files:** `scripts/input/StickPoller.gd`, `scripts/player/SkaterController.gd`

> Came out of a physics-systems audit prompted by "lots of weird *feel* issues when riding, and
> doing tricks in general", with a standing instruction to prefer **reduction** over patches and to
> let physics rather than authored curves drive controls.
>
> The audit found one wrong-layer curve and one missing conservation law that are cheap and clearly
> correct, and four structural issues that are real but need a play verdict or their own commit. The
> split is the point of this document: **items 1–2 shipped, items 3–6 are written down so they are
> not rediscovered from scratch.**

---

## ✅ 1. `lean` carried a perceptual curve in the DEVICE layer

`StickPoller.poll()` reported `lean = sign(rt - lt) · |rt - lt|^2.2` — an "audio-log taper" added to
desensitise light-to-mid trigger squeezes for **mid-air spin styling**.

**Carving paid for it, and nothing could see that it was.** A carve is $\omega = v/R$ with
$R = $ `carve_radius_m` $/$ `lean`, so a curve on `lean` is a curve on **curvature**:

| trigger pull | `lean` after taper | carve radius at full-lean $R = 3\text{ m}$ |
|---|---|---|
| $0.25$ | $0.047$ | $63.4\text{ m}$ |
| $0.50$ | $0.218$ | $13.8\text{ m}$ |
| $0.70$ | $0.453$ | $6.6\text{ m}$ |
| $0.85$ | $0.693$ | $4.3\text{ m}$ |
| $1.00$ | $1.000$ | $3.0\text{ m}$ |

Half a trigger produced a $13.8\text{ m}$ arc where the model says $6\text{ m}$. Most of the usable
steering lived in the top $20\%$ of travel — which is precisely the "board does nothing, then
suddenly bites" complaint, and it is **not** what 07a fixed. 07a corrected the *model*; this sat
upstream of the model and rescaled its only input.

**The suite could never have caught it.** `carve_and_push` has a dedicated case —
*"carve radius @4, half lean"* — asserting that half lean **doubles** the radius, because lean maps
to a truck steer angle and curvature is what is linear in that angle. But the harness writes
`rider.lean` directly, bypassing the poller. So the suite has been asserting the linear law for as
long as the taper has been violating it. **That is the general hazard, not a one-off: a physical
quantity shaped at the hardware boundary is invisible to everything downstream, including its own
tests.**

**Shipped:** `s.lean = rt - lt`. Linear. Three lines became one.

The rationale for a taper was never wrong — it was in the wrong place. If mid-air spin wants
desensitising, it belongs on the single line in `RiderBody.advance_spin()` that consumes `lean`,
where the ground is not charged for it. Note the air already has inertia there (`spin_response`), so
it may not need one at all.

## ✅ 2. Angular momentum did not cross the takeoff

`_apply_steering()` drops `_steer_rate` to zero the moment the skater is airborne, and
`RiderBody.spin_rate_deg` was left at zero by the previous touchdown's `halt_spin()`. So on the pop
frame the rider's yaw rate went to zero and airborne spin then eased in **from zero**.

**Leaving the ground removes the torque on the rider, not their rotation.** Popping out of a full-lean
carve at $7\text{ m/s}$ means $\approx 134°/s$ of yaw simply vanishing at takeoff, and if the trigger
is still held, the airborne spin climbs back up from nothing. This is the same class of defect
[07b](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/features/07b_ROTATION_DYNAMICS.md) found on the deck's own rotation — infinite angular acceleration at a boundary — in the
one rotation nobody had checked. 07b gave the *deck* angular acceleration; the *body* still had none
across the ground/air transition.

**Shipped:** one line in `_execute_pop()` —
`rider_body.spin_rate_deg = rad_to_deg(_steer_rate)`.

Assignment rather than accumulation is safe and provably so: `advance_spin()` runs only airborne and
`halt_spin()` zeroes the rate at every touchdown, so the shoulders are at rest at that point.
`_steer_rate` is still the live grounded value — `_apply_steering()` drops it on the first *airborne*
frame, which is the next one. Both sides apply yaw as minus-rate, so the rotational sense carries
across unchanged; only the unit differs.

**Effect in play:** a carve now becomes a spin instead of being discarded and restarted. With the
trigger released at the pop, rotation decays over ~5 frames under the rider's own inertia rather than
stopping in one.

### ⚠️ Both are deliberate feel changes with ZERO suite coverage

All five suites are **byte-identical** after both changes, and that is a statement about the
harnesses rather than about the changes:

- Every suite writes `rider.lean` or raw stick vectors directly, so **none of them has ever executed
  the taper.**
- No suite pops while leaning. `ground_physics` and `carve_and_push` both have lean cases and both
  have pop cases, but they are different code paths — the landing cases `return` before lean is
  written, and `_poll_inputs()` zeroes lean with no device attached, so `_steer_rate` is $0$ on every
  scripted pop frame.

So byte-identical here means **"not covered"**, not "no-op". Both need a play verdict, exactly as 07a
and 07b did. If either is wrong, it is wrong in a way no assertion currently sees — a suite case that
pops while leaning is the cheapest thing to add next.

## ✅ Also shipped — two pure reductions, no behaviour change

- **`flat_velocity` computed property.** `Vector3(velocity.x, 0.0, velocity.z)` was rebuilt inline at
  six call sites. One of them, `_apply_grounded_board_pitch()`'s kickturn gate, had hand-derived
  `current_speed` rather than calling it.
- **`_apply_grounded_board_pitch()` declared a local `is_manualing`, shadowing the `is_manualing()`
  method for the rest of the function**, and tested `abs(pitch) > 2.0` against a hardcoded literal
  that duplicates `manual_pitch_min_deg` (also $2.0$). The local is now `pitch_requested` — it asks a
  genuinely different question ("did an input request a pitch") than the method ("is the rider
  balanced on one truck") — and the literal is the export.

---

## 🔍 Findings NOT acted on

Each is real, each is a reduction, and each needs either a play verdict or its own commit with its own
re-baseline. **Ordered by how much they are likely contributing to "weird feel".**

### 3. 🔨 Seventeen first-order lags are standing in for inertia — and a lag is not inertia

`lerpf(x, target, rate * delta)` appears ~17 times across the player scripts: `surface_align_speed`
$12$, `airborne_pitch_follow` $14$, `grounded_pitch_follow` $16$, `steer_response` $20$,
`spin_response` $20$, `twist_follow` $1000$, `landing_dip_recover` $9$, plus five on the camera.

**Two separate problems.**

**(a) The shape is wrong for what it is being asked to model.** A first-order lag has **no momentum**:
it cannot overshoot, cannot coast, and responds *hardest on the first frame*. At `steer_response = 20`
and $dt = 1/60$ the board covers $33\%$ of the gap to the new rate in frame one and then crawls
asymptotically. `SkaterController.gd`'s own comment says this lerp is what gives the ground "the
inertia the air already had" — but what it actually produces is a fast bite followed by a vague tail,
which is a fair description of *both* live complaints. Real rotational inertia is second-order:
bounded angular **acceleration**, i.e. `move_toward(rate, target, ang_accel * delta)` — a constant
slope, which is what a constant torque on a constant mass gives. That is also a *reduction*: one
physical quantity (angular acceleration) replaces a dimensionless "response rate" whose units mean
nothing.

**(b) `rate * delta` is not frame-rate independent.** The correct exponential form is
$1 - e^{-rate \cdot \Delta t}$. At the fixed $60\text{ Hz}$ physics tick this is latent rather than
live — but every one of these constants is silently calibrated to $1/60$, so changing the tick would
move all seventeen at once, in different directions from their tuned values. At `rate = 20`:
$20/60 = 0.333$ against $1 - e^{-0.333} = 0.284$.

**Why left:** (a) is a genuine feel change on the sim's most-touched control and needs playing, not
asserting — the same call 07a and 07b both made. (b) should not be fixed piecemeal; it moves every
figure in every suite for no felt benefit at a fixed tick, and is better done as one deliberate
re-baseline if the tick ever changes. **Do (a) for `_steer_rate` first, alone, and play it.**

### 4. 🔨 `_is_carve_latched` is a hysteresis latch hiding a rate discontinuity

Two entirely different steering laws switch on a speed latch: carve ($\omega = v/R$, decays to nothing
as speed does) and kickturn (a flat $3.0\text{ rad/s} \approx 172°/s$, speed-independent by design).
The latch sets above `kickturn_max_speed` $0.5$ and clears below $0.05$, and it may only be
re-evaluated while the rider is actually leaning — otherwise a carve released at speed winds down
through the **kickturn** branch, which translates the rig.

**Roll to a near-stop while holding a turn and the target rate jumps from $\approx 0.017\text{ rad/s}$
to $3.0$ — a factor of ~176 — as the latch clears.** The `steer_response` lerp smears it over a few
frames, but the board stops arcing and starts pivoting on the spot, which is a regime change the rider
never asked for. This is the most likely remaining cause of "carving does not flow at low speed", and
it is downstream of 07a rather than fixed by it.

**Done looks like:** deleting the latch and making the total steer rate a **sum** — the carve term
$v/R$ always, plus a kickturn term gated on the nose actually being lifted, which the code already
does automatically at low speed via `kickturn_pitch_deg`. Both are then continuous and no threshold
decides which physics applies. **The hard part is the axle anchoring**, which currently belongs to the
kickturn branch outright and would have to be applied in proportion to the kickturn term.
`carve_and_push` has dedicated kickturn cases with `max_pos_jump` assertions that must hold.

### 5. 🕳️ Two vertical systems, neither of them a contact

While grounded, `_integrate_position()` hard-assigns `global_position.y = _surface_ride_y()` every
frame — zero lag, zero give — while `_apply_surface_alignment()` *lerps* orientation at $12/s$
(~5 frames). **Height tracks the terrain exactly while tilt arrives late.** Rolling onto a ramp, the
board is already at the ramp's height before it has finished rotating onto its face; rolling over a
curb edge, the rig teleports vertically.

Separately, `landing_dip` is a purely cosmetic compression lerped on `SurfaceAlign.position` — its own
comment is careful to say it is *not* the fix for harsh landings and that setting it to $0$ disables it
cleanly. So there are two vertical systems and neither is a suspension: one is a rigid constraint, the
other is decoration.

**Done looks like:** one contact spring-damper in the vertical replacing both — the snap becomes a
stiff spring, the dip becomes its compression, and the same integration gives ramps, curbs and
landings their give for free. **That is net new physics, not a reduction**, which is why it is filed
rather than done — but it would *delete* `landing_dip_max` / `landing_dip_ref_speed` /
`landing_dip_recover` and the separate recovery pass. Cheapest partial win, if the full spring is not
wanted: match `surface_align_speed` to the snap's zero lag so tilt and height stop disagreeing.

### 6. 🕳️ The deck's rotation has five overlapping modes

`is_flip_in_progress` × `_flip_free_spinning` × `is_flip_settling`, plus turn counts, derived targets,
`_spin_up_scale()`, `_catch_scale()`, `_settle_target()` and `_credit_achieved_rotation()` — roughly
250 lines to spin one deck. The comments are excellent and every mode has a real bug behind it, so this
is **earned** complexity, not accidental.

But two signals suggest the model is fighting itself:

- **`flip_catch_floor` exists only because `move_toward` with a decaying rate never arrives.** A
  deceleration keyed to *distance remaining from a target* needs a floor bolted on to guarantee
  completion. Angular velocity plus a restoring torque toward the nearest resting orientation arrives
  on its own.
- **Two independent decelerators**, `_catch_scale()` and `_advance_flip_settle()`, with a documented
  rule that they can never both act because they sit in different branches. A rule of that shape is
  usually a sign the two are the same physical event modelled twice.

**Why left:** highest reward and by far the highest risk in the audit. Five suites are keyed to these
timings and the whole held-rotation feature is built on the turn-count state, which the docs correctly
identify as irreducible (geometry alone cannot say a $360$ scoop is not finished at $180$). **Do not
attempt this as a cleanup.** It is a rewrite with its own spec, and it should be attempted only if
items 3–5 have not already fixed the felt problem.

### 7. 🕳️ Reinforcing [CLEANUP #3](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/CLEANUP.md) — the one-frame input lag is a feel bug, not just debt

`SkaterController` ticks before `RiderInput`/`TrickState` (tree order), so **every** frame acts on
sticks sampled the previous one: ~$16.7\text{ ms}$ added to steering, pops and flicks. CLEANUP #3
records this accurately as pre-existing and un-verifiable as a no-op.

Worth restating here because the audit's brief was feel: for a game whose core input is a *flick*, a
frame of latency on the flick is a first-order feel cost, and it is already visibly leaking into the
physics — `flip_unwind_max_deg`'s own comment notes that "about 2 frames of rotation are spent before
the settle engages, since `flick_held` is computed by `TrickState`, which ticks after the controller
reads it." That is a physical budget being spent on a scheduling artefact. The fix is a reduction
(drive `RiderInput`/`TrickState` explicitly from the top of the pipeline, as `ChaseCamera.follow()`
and `FootRig.solve()` already are, and delete the tree-order dependency).

**Not done here because it re-baselines all five suites at once**, which would have hidden whether
items 1–2 did anything. It should be its own commit, and it should probably be the next one.

---

## ✅ Verification — as run

All five suites: **12/12, 21/21, 17/17, 16/16, 16/16, zero failures, and byte-identical to the
commit before** (`diff` on captured stdout, not just `PASS` counts). `--headless --quit` clean of
parse errors.

**No figure moved, and §"deliberate feel changes with ZERO suite coverage" above explains why that is
weaker evidence than it looks** — the harnesses bypass the taper entirely and never pop while leaning.
The two reductions (`flat_velocity`, the `is_manualing` shadow) *are* genuine no-ops: same arithmetic,
and `manual_pitch_min_deg` defaults to the $2.0$ literal it replaced.
