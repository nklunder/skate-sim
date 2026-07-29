# 🛞 07a. Carve Curvature — turning must depend on speed
**Status:** ✅ `IMPLEMENTED` (awaiting play verdict) | **Parent:** [07_FEEL_TUNING.md](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/features/07_FEEL_TUNING.md) | **Key file:** `res://scripts/player/SkaterController.gd` (`_apply_steering`)

---

## ✅ What shipped

`carve_radius_m = 3.0` on `SkateBoardConfig` replaces `turn_speed`. Carving is now
`turn_rate = speed × lean × _lean_authority() / carve_radius_m`; the kickturn branch keeps a flat
rate of its own (`kickturn_rate = 3.0` rad/s, the exact figure the shared `turn_speed` produced, so
that branch is unchanged).

**Measured, at full lean:** radius $3.00\text{ m}$ at $7$, $4$ and $2\text{ m/s}$ alike, at
$121.7$, $66.4$ and $28.6°/\text{s}$. At half lean, $6.00\text{ m}$.

**The old model, measured the same way:** a flat $171.9°/\text{s}$ at every speed — a $2.09\text{ m}$
radius at $7\text{ m/s}$, $1.12\text{ m}$ at $4$, and **$0.50\text{ m}$ at $2\text{ m/s}$**. That last
figure is the whole complaint: a half-metre carve radius is a pivot, not an arc.

The remaining question is a **play** one — whether $3\text{ m}$ is the right number, and whether
low-speed carving now flows. That verdict is what decides how much of 07b/07c is worth doing.

---

## 🔍 The measured problem

`_apply_steering()` turns the rig at a rate that has **no speed term at all**:

```gdscript
var turn_rate: float = rider.lean * turn_speed * _lean_authority()
rotate_y(-turn_rate * delta)
```

At full lean that is a flat $\approx 169^\circ/\text{s}$ whether the skater is doing $7\text{ m/s}$ or
$1\text{ m/s}$. Measured directly, and `carve_and_push` records the same figure at both its test
speeds.

**Physically, lean sets a turn RADIUS, not a turn rate.** A truck's bushings deflect by an amount set
by how hard the rider leans; that deflection is a steering angle; the steering angle and the wheelbase
give a radius. Angular velocity is then $\omega = v/R$ — so the same lean carves *the same arc* at any
speed, and the angular rate rises with speed.

Taking a $3\text{ m}$ radius at full lean as a starting point (**an assumption to be tuned, not a
measurement**):

| speed | physical $\omega$ | current $\omega$ | error |
|---|---|---|---|
| $7\text{ m/s}$ | $\approx 134^\circ/\text{s}$ | $169^\circ/\text{s}$ | ~1.3× |
| $4\text{ m/s}$ | $\approx 76^\circ/\text{s}$ | $169^\circ/\text{s}$ | ~2.2× |
| $2\text{ m/s}$ | $\approx 38^\circ/\text{s}$ | $169^\circ/\text{s}$ | **~4.4×** |

So the model is roughly calibrated for fast riding and **badly wrong when slow**. That is exactly
where flow breaks down: at walking pace the board spins on the spot instead of arcing, which reads as
darty and twitchy rather than weighted.

## 🛠️ The model

A **kinematic two-axle (bicycle) steering model** — the standard approach, and it needs no exotic
research:

```
lean  ->  truck steer angle  ->  turn radius R  ->  omega = v / R
```

`SkateBoardConfig.turn_speed` becomes a *radius-like* quantity (or is replaced by one) rather than an
angular rate. Everything speed-dependent then falls out with no special cases.

**Secondary, and smaller:** grounded steering is applied instantly, with no inertia, while *airborne*
body spin lerps toward its target at `RiderBody.spin_response = 20.0`. That asymmetry is felt. Giving
the ground the same treatment costs one lerp.

## 🔗 Interactions to check

- **`kickturn_max_speed` becomes less of a special case.** Stationary kickturns exist today precisely
  because the constant-rate model produces nonsense at low speed. Under $\omega = v/R$ the rate falls
  to nothing on its own as speed does, so the kickturn path may simplify — but it must NOT be deleted
  casually: it also anchors rotation on the trailing axle (BUG_ARCHIVE #6), which is a separate and
  still-necessary job.
- **`_lean_authority()` is unaffected.** It answers "how much weight is available to lean with" and
  stays a multiplier on the lean, wherever the lean is then used.
- **`_is_carve_latched`** exists to stop a mid-carve deceleration snapping into kickturn mode. If the
  two regimes converge, the latch may become unnecessary — verify rather than assume.
- **Grip and the landing residual are untouched.** Turning generates lateral speed which
  `_apply_ground_forces()` scrubs; that mechanism is unchanged, but the *amount* of lateral generated
  per frame changes, so re-check the carve speed-cost figures.

## ✅ Verification — as run

All five suites pass (12/12, 19/19, 17/17, 16/16, 16/16). `curb_flip_repro`, `foot_rig` and
`pop_gesture` are **byte-identical** to before, which is correct: none of them carve.

**The probe was written**, and it is now the load-bearing assertion. Four cases sample $R = v/\omega$
per frame — three speeds plus a half-lean case — because swept degrees are a bad invariant under this
model: they change with speed *by design*, so a bound on them measures the test's starting speed as
much as the physics.

**Falsified before being trusted:** against the old flat-rate model all four fail (reporting the
$2.09/1.12/0.50\text{ m}$ radii above). Against a model where lean *multiplies* the radius, only the
half-lean case fails — the three full-lean cases stay green, since at $\text{lean} = 1.0$ every
formulation coincides. That is exactly why the half-lean case has to exist.

> ⚠️ One earlier "falsification" was worthless and is worth recording: rewriting the term as
> $R/\text{lean}$ instead of $\text{lean}/R$ is the *same equation rearranged*, and it passed because
> it was not a different model at all.

**Figures that moved, and why:**

| Case | Before | After | Why |
|---|---|---|---|
| `carve @7, no push` | $340.9°$ | $219.0°$ | $120$ frames no longer completes a lap; a $3\text{ m}$ circle at $7\text{ m/s}$ is $360°$ in ~$2.7\text{ s}$, not ~$2.1$. Bound $300 \to 190$ |
| `steer in a shallow manual` | $138.7°$ | $53.8°$ | $76°/s$ at $4\text{ m/s}$ × $0.8$ damping. Bound $100 \to 45$; the pop-damping cliff it guards would give ~$14°$, so it still catches it wide |
| `steer in a DEEP manual` | $127.2°$ | $48.9°$ | as above — and the shallow/deep gap holds at ~9%, so the cliff test is intact |
| `kickturn + push from rest` | $739.7°$ | $418.4°$ | pushes carry it past `kickturn_max_speed`, so the latched carve portion now turns less |
| landing/skid cases | $426.9°$ | $228.1$–$253.8°$ | less steering, and settled off-axis **improved** ($2.9 \to 1.6$–$1.8$): less steering-generated lateral means the grip cap clears more easily. `max_realign_frames` unmoved at $16$/$17$ |
| `ground_physics` "carve: turns, keeps speed" | $169°$, $7.00 \to 5.56$ | $120°$, $7.00 \to 5.78$ | the only line that moved in that suite. Less turning ⇒ less lateral scrub ⇒ **less** speed cost, which is the grip coupling behaving correctly |

**Unchanged, as required:** both `check_anchor` cases are identical down to the axle drift figures
($\text{lead } 0.860$, $\text{trail } 0.041$), and `kickturn @0.3` / `@0.45` still report $570.1°$.
The trailing-axle anchoring job (BUG_ARCHIVE #6) was not touched, and the kickturn branch was kept on
its own rate specifically so it would not be.

## ❓ Open

- **What radius at full lean?** Shipped at $3\text{ m}$ and **confirmed good in play** — still an
  assumption rather than a measurement, but no longer an urgent one. Tunable from the inspector
  between runs as a live `SkateBoardConfig` export.
- **`carve_radius_m` IS bushing tightness**, so it is the first hardware property with a real physics
  knob behind it. An in-game slider was considered and **deferred to [06](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/features/06_MODULAR_HARDWARE_CUSTOMIZATION.md)** rather than half-built
  into the settings menu — which pauses the game, so a slider there would be adjust-close-ride rather
  than live. 06 records the front/rear split question and why one slider over two stored values.
- ~~Whether to keep a small floor~~ — **decided:** no floor. The stationary kickturn owns the range
  below `kickturn_max_speed`, and it keeps its own flat rate precisely so it can.
- **Deferred, and deliberately:** grounded steering is still applied instantly while airborne body
  spin lerps at `spin_response = 20.0`. One lerp on `turn_rate` closes it. Held back so the
  `carve_and_push` re-baseline had exactly one cause; it will move the swept-degree figures again
  (a ramp-in shaves off total swept), but nothing structural.
- **Rolling fakie still steers the way it always did.** `speed` is the unsigned planar magnitude, so
  a board rolled backwards turns the same way it would rolling forwards. A real board reverses. Left
  alone because the sign has consequences for `_travel_axis_sign` and the landing residual, and that
  is its own change rather than a rider on this one.
