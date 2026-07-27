# 🛹 06. Modular Hardware & Apparel Customization (Swappable Components)
**Status:** 💡 `PLANNED` | **Priority:** `MEDIUM / FUTURE` | **Key Files:** [res://scripts/player/SkateDeckMesh.gd](file:///Users/nicholasklunder/Projects/skate-sim-v-2/scripts/player/SkateDeckMesh.gd), [res://scenes/player/SkaterRig.tscn](file:///Users/nicholasklunder/Projects/skate-sim-v-2/scenes/player/SkaterRig.tscn)

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

### 3. Wheels (`Slot_Wheels`)
- **Ride Height Independence:** While wheel diameters may vary slightly (e.g., $52\text{mm} \to 56\text{mm}$ street vs. transitional wheels), `@export var ride_height: float = 0.078` in `SkaterController.gd` can be updated dynamically upon equipment swap so ground clearance remains perfectly matched!

---

## 👟 Swappable Character Apparel & Footwear
- **Hero Shoe Slots:** Right now, shoes are US 11 M box meshes at `X = -0.025m`. In full customization, these become interchangeable 3D footwear models ($1,500 \to 3,500$ triangles each, origin set exactly at anatomical ankle hinge).
- **Apparel Customization:** Pants, hoodies, hats, and accessories swapped cleanly across modular skeletal mesh layers attached to our humanoid skeleton (see [05_FULL_CHARACTER_RIG.md](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/features/05_FULL_CHARACTER_RIG.md)).
