# 🔊 03. Procedural Sound Design Engine (Tactile Audio Feedback)
**Status:** 🚧 `PLANNED` | **Priority:** `HIGHEST` | **Target Script:** `res://scripts/player/SkateAudioEngine.gd`

---

## 🎯 Executive Summary & Video Game Audio Architecture
In an authentic physics-driven skateboarding simulator, sound is half the tactile interface. When rolling across pavement, carving around corners, popping high off ledges, and catching spinning decks mid-air, auditory cues convey physical momentum and weight before the eyes even parse visual animation details. 

### Interactive Sample Modulation vs. Pure Synthesis
Modern simulator sound design almost never relies on purely synthesized computer noise (which sounds robotic and unnatural). Instead, we employ **Interactive Blended Sampling**:
1. **High-Fidelity Source Samples:** Real-world audio recordings of physical skateboard hardware (e.g., a seamless 4-second loop of polyurethane wheels cruising over asphalt, a sharp transient of a maple deck crack popping off concrete, or steel truck hangers scraping against an iron rail).
2. **Real-Time Procedural Math (Modulation):** GDScript dynamically alters the volume (dB attenuation), playback speed (pitch scale / RPM simulation), and frequency equalization of those audio clips every frame based on authoritative kinematics in [SkaterController.gd](file:///Users/nicholasklunder/Projects/skate-sim-v-2/scripts/player/SkaterController.gd).
3. **Zero-Overhead Asynchronous Processing:** Because Godot 4 processes interactive audio asynchronously on a dedicated audio mixer thread, managing multi-surface matrices and dozens of simultaneous modulated audio channels costs virtually **zero graphics or physics CPU overhead**.

---

## 🚀 Phase 1 Foundation: Core Rolling, Jumping & Touchdown Audio
Before integrating Stage 2 grind mechanics, our immediate target is a rock-solid, highly responsive foundational audio engine covering fundamental street riding:

```
SkaterRig (Root Scene)
└── SkateAudioEngine [Node3D] (Script: res://scripts/player/SkateAudioEngine.gd)
    ├── RollingLoop [AudioStreamPlayer3D] — Seamless pavement wheel rumble
    ├── AirRushLoop [AudioStreamPlayer3D] — Aerial flight wind & high-speed spins
    ├── PopPlayer [AudioStreamPlayer3D] — Randomized maple tail snap transients
    ├── CatchPlayer [AudioStreamPlayer3D] — Rubber shoe-on-griptape catch thuds
    ├── LandingPlayer [AudioStreamPlayer3D] — Concrete touchdown stomps (descent-scaled)
    ├── SkidPlayer [AudioStreamPlayer3D] — Polyurethane power-slide screeches
    └── PushScuffPlayer [AudioStreamPlayer3D] — Shoe sole pavement thrust scuffs
```

### 1. Polyurethane Wheel Rumble (`RollingLoop`)
- **Source Audio:** Seamless looping stereo/3D recording of polyurethane wheels on asphalt.
- **Kinematic Modulation (Grounded State):**
  - **Speed-to-Volume Curve:** Directly driven by horizontal cruising speed:
    $$v = \sqrt{\text{velocity}.x^2 + \text{velocity}.z^2}$$
    At $v = 0.0\text{ m/s}$ (idle stand), volume drops to `-80.0 dB` (silent). As speed increases to normal cruising ($1.5 \to 7.0\text{ m/s}$), attenuation interpolates smoothly up to `0.0 dB`.
  - **Speed-to-Pitch Curve (Wheel RPM Simulation):** Faster cruising velocities rotate physical wheels at higher RPMs. We map `pitch_scale` linearly from `0.65` at slow walking speeds up to `1.15` at maximum cruising speed ($7.0\text{ m/s}$).
- **Airborne Transition:** On the exact frame `is_grounded == false`, volume drops immediately (or transitions to a subtle free-spinning wheel ball-bearing hum).

### 2. Tail Cracks & Ollie Pop Impulses (`PopPlayer`)
- **Source Audio:** Godot `AudioStreamRandomizer` containing 3 to 5 distinct recordings of wooden plywood popping against concrete.
- **Randomization Rules:** Set random pitch variance to $\pm 6\%$ (`0.94` to `1.06`) and volume variance to $\pm 1.5\text{ dB}$ so consecutive Ollie leaps never produce robotic duplicate audio playback.
- **Trigger Condition:** Executed instantaneously inside `_execute_pop()` right when upward jump impulse is applied.

### 3. Airborne Rush & Body Spins (`AirRushLoop`)
- **Source Audio:** Soft looping stereo wind rush.
- **Kinematic Modulation:** Fades in when flight height exceeds $0.4\text{m}$ or when shoulder triggers unleash high-velocity aerial body rotation (`spin_speed_deg = 554 deg/s`), reinforcing spatial awareness during gap stunts.

### 4. Griptape Catch, Landings & Skids (`CatchPlayer`, `LandingPlayer`, `SkidPlayer`)
- **Mid-Air Catch Thud (`CatchPlayer`):** A clean rubber-on-griptape slap triggered mid-air when `_credit_achieved_rotation()` or `_advance_flip_settle()` registers that a spinning skateboard has been safely arrested by the player's shoes.
- **Touchdown Stomp (`LandingPlayer`):** Triggered on landing (`!was_grounded && is_grounded`). Impact volume and low-frequency bass punch scale directly with descent velocity (`abs(previous_vertical_velocity)`):
  - Small manual curb hop ($1.0\text{ m/s}$ descent) $\to$ light wooden tap (`-12 dB`).
  - Giant platform drop ($4.0+\text{ m/s}$ descent) $\to$ thunderous structural concrete slam (`0 dB`).
- **Sideways Skid Screech (`SkidPlayer`):** Triggered when touching down near the $\pm 45^\circ$ alignment tolerance window (where wheel grip anisotropy scrubs angular velocity) or during aggressive high-speed slides.

### 5. Foot Push Scuffs (`PushScuffPlayer`)
- **Trigger Condition:** Synchronized directly to `FootRig.gd` during push strokes at the precise animation frame where the shoe sole sweeps backward against pavement to generate forward propulsion.

---

## 🛹 Stage 2 Blueprint: The Dynamic Surface & Hardware Contact Matrix
As our Stage 2 Grind and Slide mechanics materialize (see [02_GRIND_SYSTEM.md](file:///Users/nicholasklunder/Projects/skate-sim-v-2/docs/features/02_GRIND_SYSTEM.md)), sound design expands into a fully dynamic **Multi-Surface & Component Matrix**. This architecture avoids complexity by separating terrain probing from hardware contact facts.

```
       [ Surface Probe Metadata ]               [ Hardware Contact Component ]
     ( Concrete | Metal Rail | Stone )    x    ( Polyurethane Wheels | Steel Trucks | Wood Deck )
                                          │
                                          ▼
                      [ Acoustic Matrix Audio Selection & Resonance ]
```

### 1. Axis A: Surface Material Metadata
When [SurfaceProbe.gd](file:///Users/nicholasklunder/Projects/skate-sim-v-2/scripts/physics/SurfaceProbe.gd) inspects floor and ledge geometry via Godot physics queries, colliders are tagged with custom physics material IDs or collision layers:
- `SurfaceType.CONCRETE` / `ASPHALT` (Standard rough pavement)
- `SurfaceType.METAL_RAIL` (Iron handrails, steel coping pipes)
- `SurfaceType.STONE_LEDGE` (Polished granite, brick, rough concrete ledges)
- `SurfaceType.WOOD_RAMP` (Plywood half-pipes, transition ramps)

### 2. Axis B: Hardware Component in Contact
Our controller natively distinguishes which part of the skateboard assembly is grounded or sliding:
- **`WHEELS_POLYURETHANE`:** Four wheels rolling across terrain. (e.g., Asphalt produces gritty hum; Wood Ramp produces warm hollow rolling rumble).
- **`TRUCK_STEEL_AXLE`:** Steel truck hangers grinding across ledges or coping.
- **`DECK_WOOD_BOTTOM`:** Maple plywood underside sliding across obstacles during Boardslides, Tailslides, or Noseslides.

### 3. Contact Matrix Examples & Acoustic Resonance Differentiation
By cross-referencing Surface $\times$ Component, the audio engine accurately produces nuanced real-world acoustic behavior:

| Hardware Component | Surface Material | Resulting Audio Profile & Feel |
|---|---|---|
| **`DECK_WOOD_BOTTOM`** | **`METAL_RAIL`** | Smooth glide hiss accompanied by a resonant hollow metal handrail ping. |
| **`DECK_WOOD_BOTTOM`** | **`STONE_LEDGE`** | Coarse, abrasive structural grinding rasp as wood scrapes rough granite. |
| **`TRUCK_STEEL_AXLE`** | **`METAL_RAIL`** | High-pitched steel-on-steel clinking chime and rapid, low-friction glide ringing. |
| **`TRUCK_STEEL_AXLE`** | **`STONE_LEDGE`** | Grinding crunch with heavy low-mid frequencies as metal gouges masonry. |

### 4. Contact-Point Resonance Scaling (1-Truck vs. 2-Truck Grinds)
Furthermore, grind sounds dynamically scale depending on how many points of contact are locked onto the ledge:
- **Two-Truck Grinds (50-50):** Both front and rear truck axles are firmly clamped against the rail. The grind audio loop plays at **full volumetric gain (`1.0`)** with deep, balanced acoustic resonance.
- **Single-Truck Grinds (5-0, Nosegrind, Crooked, Smith):** Only a single truck axle (`manual_axle_z = ±0.225m`) bears the weight while thumbstick tilt suspends the opposite truck into open air. The audio loop scales to **lighter gain (`0.65`)** with slightly **elevated treble frequencies**, simulating lighter frictional drag and the higher cantilever resonance of an angled deck!

---

## 🛠️ Recommended Asset Pipeline, Editing Rules & Online Sourcing

### 1. Audio File Formats in Godot 4 (`.WAV` vs. `.OGG`)
In video game development, sound format selection is governed by whether a clip is an instantaneous transient or a continuous stream:

| Format | Best Applied To | Why Use It in Godot? |
|---|---|---|
| **`.WAV` (16-bit, 44.1 kHz, Uncompressed)** | Short instantaneous impacts: **Ollie Pops, Foot Scuffs, Catch Thuds, Landing Stomps** ($< 1.0\text{ sec}$) | Uncompressed WAV resides natively in RAM with **zero CPU decompression overhead**, guaranteeing instantaneous triggering with zero audio latency when popping maneuvers. |
| **`.OGG` (Vorbis, 44.1 kHz, Quality 5–7)** | Continuous looping audio: **Pavement Wheel Rumble, Air Rush Wind, Metal Grinds** ($2.0 \to 10\text{ secs}$) | Compressed OGG drastically reduces filesize (e.g., a 5 MB WAV compresses down to $\sim 300\text{ KB}$ OGG). Godot decodes these loops streaming in real time without hogging memory! *(Note: Never use `.MP3` for looping game sounds; MP3 encoding inherently injects micro-silence frames at file headers/footers, causing audible clicking gaps when looped).* |

### 2. Audio Editor Preparation & Cutting Rules (Audacity / DAW Guidance)
When processing audio samples in a free audio editor like **Audacity** or Reaper, adhere to these three game audio rules:

#### A. Rule of Transients: "Shave Leading Silence" (Zero Latency Calibration)
- Downloaded field recordings almost always contain 5 to 50 milliseconds of ambient room hiss or pre-roll silence before an impact transient occurs.
- **Action:** Zoom closely into the exact leading edge where the waveform spikes sharply upward and **delete all leading silence**. The initial microsecond of the exported `.wav` must begin at the exact start of physical impact so player controls never feel disconnected or delayed!

#### B. Rule of Looping: "Zero-Crossing & Crossfades"
- For looping wheel rumble or grind slides, mismatched starting and ending amplitude phases will generate a harsh *CLICK* or *POP* artifact upon loop restart.
- **How to forge seamless game loops:**
  1. **Crossfade Slicing:** Take a 4-second continuous recording of skate wheels. Split the clip in half at the exact midpoint (Left half A, Right half B). Swap their positions so section B plays first and section A follows. Now overlap their central boundary by 0.5 seconds and apply an audio crossfade! The outermost starting and ending boundaries now mate seamlessly with zero sudden audio changes.
  2. **Zero-Crossing Snapping:** When trimming loop end-points, snap your selection edits directly to a "zero-crossing" (where the waveform smoothly intersects the center zero-decibel axis) to eliminate boundary clicks.

#### C. Rule of Headroom: "Normalize to -1.0 dB"
- **Action:** Normalize all final audio sample exports to a ceiling peak between `-1.0 dB` and `-0.5 dB`. This preserves mixing headroom and prevents digital distortion/clipping when multiple simultaneous audio channels (rolling + air rush + pop snap) sum together in Godot!

### 3. Recommended Sample Durations
- **Ollie Pops & Tail Snaps (`.wav`):** `150 ms` to `350 ms` (Keep punchy; trim trailing street reverb so it doesn't bleed into mid-air silence).
- **Landing Touchdown Stomps (`.wav`):** `300 ms` to `600 ms` (Allows low-frequency concrete bass energy to ring out).
- **Shoe Push Scuffs (`.wav`):** `200 ms` to `400 ms`.
- **Griptape Rubber Catch Thud (`.wav`):** `100 ms` to `200 ms`.
- **Pavement Wheel Rumble (`.ogg`):** `3.0` to `6.0 seconds` seamless loop (Loops under 1.5s create repetitive, distracting mechanical rhythms; 4+ seconds conceals repeating patterns).
- **Grind & Slide Rumble (`.ogg`):** `2.0` to `4.0 seconds` seamless loop.

### 4. Recommended Online Audio Repositories (No Mic Needed)
High-fidelity skate and architectural Foley sounds can be sourced from established online repositories without requiring studio microphones:

#### A. Free & Open Repositories (Zero Cost)
1. **Freesound.org (Creative Commons & CC0):**
   - Essential search queries: *"skating asphalt loop"*, *"skates wheels rolling"*, *"skateboard ollie pop"*, *"concrete jump landing"*, *"metal rail scrape"*.
   - Filter results by **"License: Creative Commons 0 (CC0 / Public Domain)"** for unrestricted, commercial-safe integration.
2. **Sonniss GDC Audio Archives:**
   - Every year during GDC, Sonniss distributes massive multi-gigabyte bundles of commercial-grade sound effects completely free with zero attribution obligations. Ideal for searching high-impact urban masonry, pavement scrapes, and wood breaks.
3. **Adobe Free Sound Effects Library:**
   - Open royalty-free sound repository provided directly on Adobe's creative platform, featuring crisp impact transients, wooden cracks, and urban ambiance.

#### B. Professional Sample Marketplaces
1. **Splice & Loopmasters:** Massive repositories of high-definition Foley audio packs (search for *"Skater Foley"*, *"Extreme Sports SFX"*, or *"Wood & Metal Scrapes"*). Allows cherry-picking individual short audio files for just pennies per sample using credit subscriptions.
2. **Epidemic Sound & Artlist:** Renowned among video game and video editors for authentic, ultra-clean urban action Foley recording suites.

#### C. Raw Skate Film Audio Extraction & AI De-Noising (Hacker Route)
- Sourcing Creative Commons (CC BY) raw unedited skateboard camera clips or raw skate lines from online media.
- Using modern free audio utilities (Audacity noise reduction or free AI ambient vocals/traffic strippers like UVR5), devs can isolate pristine wheel rolls, wooden tail cracks, and iron grinds directly from authentic skate filmer camera microphone feeds!

---

### 5. Engineering Scaffolding (Zero Delay Start)
While sourcing or editing authentic sound sample packs, development can commence immediately using procedural synthetic placeholder tones (e.g., filtered white noise for rolling rumble, quick percussive clicks for jumps). Once the GDScript velocity modulation formulas and node triggers are verified, replacing placeholder files with high-definition audio samples requires zero script alterations!

