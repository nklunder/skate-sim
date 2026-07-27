# 🚶 05. Full Humanoid Character Rig & Procedural IK Integration
**Status:** 💡 `PLANNED` | **Priority:** `MEDIUM / FUTURE` | **Target Node:** `SkaterRoot/CharacterBody3D_Skeleton`

---

## 🎯 Executive Summary & The "Bottom-Up" Advantage
Traditional 3D gaming often approaches character animation "top-down"—replaying pre-recorded full-body motion capture clips that drag a skateboard asset beneath feet. Skate Sim V2 deliberately embraces a revolutionary **"Bottom-Up Procedural IK"** design architecture:
1. **The Board is Authoritative:** Physics kinematics ([SkaterController.gd](file:///Users/nicholasklunder/Projects/skate-sim-v-2/scripts/player/SkaterController.gd)) govern true physical deck behavior (tilt, pop, flip, spin, slope alignment).
2. **Shoes are Autonomous:** Shoe box nodes in [FootRig.gd](file:///Users/nicholasklunder/Projects/skate-sim-v-2/scripts/player/FootRig.gd) execute independent procedural footwork (flicks, scoops, pushes, manual balance catching).
3. **The Body Adapts via Inverse Kinematics (IK):** The legs of our future humanoid 3D skeletal character will dynamically extend and compress to match those exact shoe poses as their **IK End-Effectors**!

By building foot animations first (see [01_FOOT_ANIMATIONS.md](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/features/01_FOOT_ANIMATIONS.md)), zero development effort is discarded—every flick, scoop, and push automatically controls the full leg skeleton upon attachment!

---

## 🦴 Anatomical Skeletal Mapping & Behavior Targets

### 1. Lower Body (Leg IK Engine)
- **Target Setup:** Godot 4 `SkeletonIK3D` (or modern Godot 4 skeleton modifiers/TwoBoneIK) attached to left and right leg chains (`Hip -> Thigh -> Shin -> Ankle -> Foot`).
- **Target Coordinates:**
  - Left Leg IK target simply follows `FootRig.left_foot` world transform.
  - Right Leg IK target simply follows `FootRig.right_foot` world transform.
- **Natural Knee Bend (Pole Targets):** Project pole directional targets slightly forward and outward relative to knee anatomical hinges so knees flex out naturally during deep crouches and pop loading!

### 2. Upper Body (Torso Balance & Trigger Pre-Winding)
- **Torso Center of Mass:** Center of hips/pelvis floats midway between both shoe X/Z positions at an adjustable standing height ($Y \approx 0.90\text{m}$ above deck). During `LOADING_OLLIE`, pelvis dips downward ($Y \approx 0.65\text{m}$) into an athletic crouch.
- **Analog Trigger Body Spin (Pre-Wind Mechanics):**
  - When squeezing shoulder triggers (`LT` / `RT`) before jumping, the character’s shoulders, head, and chest begin twisting horizontally in anticipation of spin momentum—pre-winding the anatomical springs before launch!
  - During mid-air spins (180s / 360s), upper torso leads the rotational turn while arms smoothly extend outward for balance conservation.

### 3. Arm Style & Manual Balance Flail
- **Manual Balance Countering:** During manual balance zones ($0.20 \to 0.90$ stick deflection), arms raise slightly outward, tilting subtly in opposition to deck pitch error to convey athletic equilibrium.
- **Airborne Style:** Arms swing naturally during jump ascents and tuck slightly inwards during rapid flip catching.
