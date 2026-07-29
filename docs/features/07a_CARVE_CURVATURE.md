# 🛞 07a. Carve Curvature — turning must depend on speed
**Status:** 🚧 `PLANNED` | **Parent:** [07_FEEL_TUNING.md](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/features/07_FEEL_TUNING.md) | **Key file:** `res://scripts/player/SkaterController.gd` (`_apply_steering`)

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

## ✅ Verification

- **`carve_and_push` re-baselines.** Its carve cases assert turned degrees directly, and every one of
  them moves. State which and why; do not adjust thresholds to hide a change.
- The kickturn anchor cases (`check_anchor`) must still pass — those are about which truck the board
  pivots on, which this does not change.
- `ground_physics` bank reversals and landings should be unaffected; if they move, that is a signal
  something coupled that should not have.
- **Probe worth writing:** turn rate and path radius sampled across $1$–$7\text{ m/s}$ at full lean,
  confirming the radius is roughly constant and the rate scales.

## ❓ Open

- **What radius at full lean?** $3\text{ m}$ is a plausible starting point, not a measurement. Real
  boards vary enormously with truck tightness — this is exactly the knob `SkateBoardConfig` should own,
  and it is the natural place for the deferred hardware-customisation work ([06](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/features/06_MODULAR_HARDWARE_CUSTOMIZATION.md)) to become real.
- Whether to keep a small floor so the board still responds when nearly stopped, or let the stationary
  kickturn own that range entirely.
