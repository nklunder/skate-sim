# 🔊 07c. Presentation Feel — sound, optical flow, and FOV
**Status:** 🚧 `PLANNED` | **Parent:** [07_FEEL_TUNING.md](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/features/07_FEEL_TUNING.md) | **Related:** [03_SOUND_DESIGN.md](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/features/03_SOUND_DESIGN.md), [04_CAMERA_AND_FILMER_MODE.md](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/features/04_CAMERA_AND_FILMER_MODE.md)

---

## 🎯 The honest position

**This is probably a large part of the missing "flow" — possibly larger than the physics gaps in
07a and 07b.** It is listed last anyway, and the reason matters:

> Presentation would **mask** a physics gap rather than fix it.

If sound and texture land first, low-speed carving will *feel* better while still being $\approx 4\times$
too fast in angular rate, and there is then no way to tell whether further physics tuning is helping.
Do 07a first, learn the answer, then come here knowing what is left to solve.

## 🔉 1. Wheel rumble — the primary speed cue

**Without it, $3\text{ m/s}$ and $7\text{ m/s}$ read almost identically no matter how good the
physics is.** Speed is felt through sound far more than through vision at ground level.

Pitch and amplitude scale with `current_speed`; surface type modulates timbre. Already specified in
[03_SOUND_DESIGN.md](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/features/03_SOUND_DESIGN.md) — this document is not a competing spec, just a statement of *why* it
belongs to the feel work.

Beyond rumble, the events that carry weight:

- **Tail crack at the pop** — gives the ollie its impact. Its intensity has a natural driver in
  `pop_impulse_scale`, which already exists and is already graded.
- **Griptape catch on landing** — the deck being stamped flat. `last_catch_error_deg` grades how
  clean it was.
- **Truck/bushing creak while carving** — the sound of the mechanism that 07a is about to model
  properly.

## 👁️ 2. Optical flow — texture is a motion cue, not decoration

Perceived speed is largely driven by **texture frequency streaming past the camera**. An untextured
world gives almost no motion parallax, so both speed and the shape of an arc are genuinely hard to
read — the rider cannot see the flow they are trying to feel.

This is why a physically correct carve can still read as floaty and vague: there is nothing in the
image changing at a rate the eye can measure.

Ground surface detail matters far more here than object detail.

## 📷 3. Speed-scaled FOV — ✅ shipped, deliberately subtle

`ChaseCamera.fov_gain_deg = 4.0` on top of the authored $75°$, reached at `fov_speed_ref`, eased at
`fov_response = 4.0` (~quarter-second constant). Measured: $75.0 \to 78.8°$ at $6.92\text{ m/s}$,
never stepping more than $0.27°$ in a frame.

**Shipped at 4° rather than the 7° first tried, and the reason is worth keeping.** Speed-FOV is a
racing-game convention; the reference this sim is chasing does not use it. Session sells speed
through sound, a low camera and real pavement texture — which is precisely the ranking this document
already argues for, with FOV third behind rumble and optical flow. "Cheap, standard and effective"
was true of the technique and misleading about the genre.

**`fov_gain_deg = 0.0` disables it completely** and nothing else changes; no other code reads FOV.

### Why it could not disturb the framing invariant

The caution below was well-placed but the guarantee turned out to be structural rather than a matter
of keeping the change small. `ground_physics._off_centre()` measures the **angle between the camera''s
forward basis and the direction to the skater** — no projection anywhere — so field of view cannot
move it in either direction. All five suites were byte-identical with the FOV in.

That also means those assertions cannot verify FOV, so it has its own: the lens must widen with
speed, stay inside `rest + fov_gain_deg`, and never step more than $1°$ in a frame. Falsified by
driving the lens straight from speed (steps of $2.98°$) and by zeroing the gain.

> ⚠️ The widen assertion was first written as a flat "moved at least $2°$". That passed only at the
> gain it was authored against and would have failed the moment the lens was made subtler —
> re-baselining a suite for a pure tuning change, the same mistake `pop_gesture`''s height bounds made
> in metres. It is now relative to `fov_gain_deg`, with a floor that still fails a dead lens.

Already listed as an objective in [04_CAMERA_AND_FILMER_MODE.md](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/features/04_CAMERA_AND_FILMER_MODE.md) ("dynamic speed FOV").

**Caution:** `ChaseCamera` holds a documented invariant — position and aim must derive from the same
smoothed yaw, or the subject leaves the frame. It has been broken once, and it did not present as a
framing bug; it read as *"the pan is too slow"*. Any FOV work must not disturb that, and the
`offCentre` assertions in `ground_physics` are the guard.

## ✅ Verification

Mostly not suite-testable — this is perceptual work, judged by playing. What the suites still protect:

- `ground_physics` camera assertions (`camStep`, `offCentre`) must not move: FOV is not framing.
- Nothing here should touch a physics figure at all. **If any suite number moves, something has
  coupled that should not have.**
