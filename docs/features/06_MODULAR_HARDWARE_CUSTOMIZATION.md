# 🛹 06. Modular Hardware & Apparel Customization (Swappable Components)
**Status:** 💡 `PLANNED` | **Priority:** `MEDIUM / FUTURE` | **Key Files:** [res://scripts/player/SkateDeckMesh.gd](file:///Users/nicholasklunder/Projects/skate-sim-v-2/scripts/player/SkateDeckMesh.gd), [res://scenes/player/SkaterRig.tscn](file:///Users/nicholasklunder/Projects/skate-sim-v-2/scenes/player/SkaterRig.tscn)

> **Truck tightness is the first slot with a LIVE physics knob** — `carve_radius_m` already is
> bushing tightness after [07a](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/features/07a_CARVE_CURVATURE.md). See [Truck tightness](#-truck-tightness--the-first-hardware-property-that-is-already-real)
> for why it ships as one slider over two stored values, and why front/rear does *not* get confused
> in switch. A UI for it was deliberately deferred here rather than half-built into the settings menu.

---

## 🎯 Executive Summary & Architectural Separation
In early development, skate rigs often combine deck wooden plies, steel trucks, polyurethane wheels, and griptape into a monolithic composite mesh. To achieve authentic personalization (garage/skatedeader menu customization), Skate Sim V2 will embrace a modular **Component Slot Architecture**. Because our kinematic engine relies on programmatic scale calibration and spatial bounding queries (such as `SkateDeckMesh.deck_extents()` and explicit wheel ride heights), separating these physical hardware elements requires zero disruption to core movement math!

---

## 🔩 Swappable Skateboard Hardware Slots

```
BoardPivot (Kinematic Anchor)
├── BoardMesh (Node3D Slot Container)
│   ├── [Slot_Deck]: Wooden maple deck (.glb model + high-res graphic underside texture)
│   ├── [Slot_Griptape]: Surface material shader (standard black, clear, cut-out grip patterns)
│   ├── [Slot_Truck_Front]: Independent front truck hanger & baseplate (silver, matte black, titanium)
│   ├── [Slot_Truck_Rear]: Independent rear truck hanger & baseplate
│   └── [Slot_Wheels]: Four independent wheel meshes (custom hardness colors, conical vs. classic shapes)
```

### 1. Wooden Skate Decks (`Slot_Deck`)
- **Geometry Standards:** Standard 8.0" to 8.5" width profiles scaled to real-world metric equivalents.
- **Graphic Application:** Underside decals driven via UV material swaps or per-fragment shader texture uniform assignments in `deck_two_tone.gdshader`.
- **Physical Bounding Preservation:** Any swapped deck automatically invokes `deck_extents()` on ready so catch cones and rail-strike angle physics dynamically calibrate to new deck lengths and widths!

### 2. Trucks (`Slot_Truck_Front` & `Slot_Truck_Rear`)
- **Axle Alignment:** Positioned precisely at our established rear contact axle coordinates (`manual_axle_z = ±0.225m`).
- **Dynamic Bushing Turn Articulation:** When carving with shoulder triggers (`_apply_steering`), truck hangers physically tilt around kingpins in direct proportion to turning rates!

#### 🔧 Truck tightness — the first hardware property that is already real

**This is the one slot that has a live physics knob today.** [07a](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/features/07a_CARVE_CURVATURE.md) made `SkateBoardConfig.carve_radius_m`
(default $3\text{ m}$ at full lean) the quantity carving is built on, and *that value is bushing
tightness* — not a metaphor for it. Tight bushings resist deflection, so a given lean produces a
smaller steer angle and a wider arc. **Looser trucks mean a smaller radius.** Exposing it needs no
new physics, only UI.

**Ship ONE slider, store TWO values.** A single "Truck Tightness" control writing both trucks is the
90% feature; per-truck tightness is a connoisseur setting and is worth *nothing* until the pivot
shift below exists. Putting both fields in the data model from the start avoids a migration later.

- **Both trucks steer, which is why a board turns so much tighter than a car.** The hangers deflect
  in OPPOSITE directions. So the **sum** of the two deflections sets the radius, and the **ratio**
  sets where the turn centre sits along the wheelbase.
- **Symmetric trucks are already modelled correctly, by accident of the obvious implementation.**
  `rotate_y()` spins about the rig origin — the board's midpoint — which is exactly where the turn
  centre belongs when both trucks deflect equally.
- **Therefore a split setup is INVISIBLE until the rotation centre moves.** A looser front truck
  shifts the centre toward the tighter rear one. Until `_apply_steering` does that, front/rear
  sliders would be two controls that sum to the same arc and feel identical — worse than not having
  them. The kickturn branch already anchors rotation on an axle and translates by the pre/post
  delta, so the mechanism exists; it is the *carve* branch that would need it.
- **Interaction to expect:** carving would start producing position motion unaccounted for by
  velocity, exactly as the kickturn does. `carve_and_push` currently reports `posJump 0.0000` for
  carves and $0.0113\text{ m}$ for kickturns; an off-centre carve pivot re-baselines that column, and
  the suite's `max_pos_jump` bound would need a carve-side figure it does not have today.

##### ⚠️ Nose/tail do NOT get confused in switch — and that is load-bearing

The natural worry is that "front" and "rear" tightness scramble during a fakie roll, a switch
landing, or a landed shove-it. They do not, and the distinction matters:

> Tightness is a property of the **deck** (the nose truck stays the nose truck), so it never changes.
> What changes is which truck is **leading**, and that swap is the real riding experience rather than
> a bug — a loose nose truck ridden switch is a loose truck *behind* you, and it genuinely feels
> different. Split setups are chosen for precisely this.

The infrastructure for it already exists because getting it wrong **was** BUG_ARCHIVE #6. Per-truck
tightness is a `BoardPivot`-frame fact and steering happens in the rig's frame, so it crosses via
`pivot_z_to_rig()` exactly as `trailing_axle_z()` does (critical rule 1), and `deck_reversed()`
already reports when the deck itself is turned 180. **Do not re-derive this from `leading_foot` or
from a raw velocity vector** — that is the mistake the archive records, in three separate consumers.

##### Tightness should eventually drive RESPONSE, not just radius

Real tightness sets two things: the steady-state radius (modelled) and how fast the truck answers a
lean — loose is twitchy and prone to wobble, tight is sluggish and stable (not modelled). The second
half is the grounded steering inertia lerp deliberately deferred out of [07a](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/features/07a_CARVE_CURVATURE.md). Until it lands, a
tightness slider moves one of the two things tightness actually does. **When it does land, one
tightness number should drive both** rather than the two becoming independent sliders.

### 3. Wheels (`Slot_Wheels`)
- **Ride Height Independence:** While wheel diameters may vary slightly (e.g., $52\text{mm} \to 56\text{mm}$ street vs. transitional wheels), `@export var ride_height: float = 0.078` in `SkaterController.gd` can be updated dynamically upon equipment swap so ground clearance remains perfectly matched!

---

## 👟 Swappable Character Apparel & Footwear
- **Hero Shoe Slots:** Right now, shoes are US 11 M box meshes at `X = -0.025m`. In full customization, these become interchangeable 3D footwear models ($1,500 \to 3,500$ triangles each, origin set exactly at anatomical ankle hinge).
- **Apparel Customization:** Pants, hoodies, hats, and accessories swapped cleanly across modular skeletal mesh layers attached to our humanoid skeleton (see [05_FULL_CHARACTER_RIG.md](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/features/05_FULL_CHARACTER_RIG.md)).
