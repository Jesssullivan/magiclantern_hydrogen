# Robotic Optics Actuation — Design Sketch

- **Date**: 2026-05-16
- **Status**: design only — **do not implement** in this initiative.
- **Linear**: TIN-1231 (Sprint C5)
- **Depends on**: `developer_guide/10_00_af_lens_telemetry.md`,
  `docs/spec/ef-mount-ttl-observation-2026-05-16.md`
- **Decoupled from**: Sprint B (imaging stack). C5 can be revisited any
  time without holding up B.

## ⛔ Do not implement yet

This is a forward-looking design sketch. Nothing in this doc is
authorized for implementation as part of the current initiative
(`magiclantern_hydrogen — house style + raw/AF research foundation`).
A separate, explicitly-scoped initiative is required before any
hardware purchases, motor wiring, or actuation code lands.

If something in here ages badly (the AF telemetry surface changes,
EF-mount RE matures, new motor controllers appear), revise this doc
before opening implementation issues.

## 1. Why this exists

Jess maintains modified Canon DSLRs (AA filter and full filter stack
removed) used as scientific instruments — LOA / satellite stacking,
spectral capture. The same cameras are increasingly used on telescopes
and microscopes where **the optical system around the camera is the
thing being actuated**, not the camera-internal AF motor.

The hypothesis: AF intent data already inside the camera (captured by
the planned `modules/af_logger/` — Sprint C2) is a good signal for
driving **external** stepper / servo motors on telescope or microscope
optics. The AF subsystem is, in effect, a high-bandwidth focus-intent
sensor with known semantics.

## 2. What we have (after Sprint C2)

`af_logger` emits `AFLG` MLV blocks containing, per AF event:

- Half-press / focus-done / shutter timestamps (hardware ticks)
- `PROP_LV_FOCUS_DATA` magnitude stream (per-vsync)
- AF point / AF area mode
- Aperture commanded
- IS state
- Lens dynamic data (DIGIC8+ only — focal length, near/far/pos, AF/MF
  switch)
- Platform capability bitmap + firmware version

This is **property-layer** telemetry, not EF-mount bus telemetry. See
the EF-mount observability bound in
`docs/spec/ef-mount-ttl-observation-2026-05-16.md`.

`tools/af-log/` (Sprint C4) renders these as timelines and classifies
focus-bracket / tracking / hunting patterns.

## 3. What we want to drive

External, **not lens-internal**, optical actuators on:

- **Telescope focusers** (Crayford, rack-and-pinion, helical) —
  typically a NEMA-17 or 14HS stepper, microstepped, with an encoder.
- **Microscope fine-focus knobs** — gear ratio + stepper assembly.
- **Filter wheel positions** — stepper or servo, indexed.

Hardware control via a host bridge (USB-attached motor driver board:
e.g. an `arduino-cli`-flashable AVR with TMC2209 drivers, or an
off-the-shelf focus controller like ZWO EAF). The host bridge presents
a serial / USB-CDC interface to a Linux/macOS host.

## 4. Architecture (sketch)

```
┌──────────────────────┐  AFLG (MLV)  ┌────────────────────┐
│  Camera (5D2/3/4)    │  on card     │  Host workstation  │
│  af_logger module    │ ───────────► │  tools/af-log      │
│  raw_vidx + RAWX     │              │  tools/raw-stack   │
└──────────────────────┘              │                    │
                                      │  optics-driver     │ ────► USB
                                      │  (planned)         │       ╰── motor controller
                                      └────────────────────┘             ╰── stepper / servo
```

Three pieces, in order of expected build time:

1. **Optics-driver host bridge protocol** — a small text/binary protocol
   over serial. "Move focuser by N steps", "go to position P", "report
   encoder", "current position". Decouples motor controller choice from
   ML side.
2. **`tools/optics-driver/`** (Zig host CLI, future) — consumes `AFLG`
   captures + live PROP feed (if/when ML grows a live property stream
   over USB/Wi-Fi) and emits motor commands.
3. **Closed-loop mode (further future)** — motor encoder feedback
   compared against AF-intent vector, PID or simpler control.

## 5. Latency budget

For static or slow-moving targets (microscope, LOA-static, deep-sky
single objects) latency tolerance is forgiving: 50–500 ms end-to-end
is acceptable.

For tracking targets (satellites, drift compensation on LOA) the budget
tightens to sub-100 ms. The current ML AF telemetry is per-vsync
(~30 Hz LiveView), which gives 33 ms granularity at the source. The
host-side processing and motor command must fit in the rest:

| Stage | Budget |
|---|---|
| Camera AF event → `AFLG` block on card | already at vsync resolution |
| Card → host (USB/Wi-Fi off-board live stream) | TBD — not built |
| Host decode + intent extraction | <5 ms (`tools/optics-driver` budget) |
| Host → motor controller | <10 ms (serial @ 115200+) |
| Motor controller → step output | <5 ms |
| **Total target** | <55 ms |

For non-tracking use, an offline `AFLG` → optics-script pipeline is
acceptable and much simpler. **Build that first.**

## 6. Hardware assumptions (sketch, not commitments)

- Motor controller: ZWO EAF (telescope) and a custom AVR + TMC2209
  board (microscope/filter wheel). Both expose USB-CDC.
- Camera side: any in-scope ML platform (`5D3.123` recommended as
  primary because of best ML maturity).
- Host: Linux or macOS workstation; Linux preferred for udev rule
  control over the USB serial device.
- Power: motor controllers powered separately from camera (USB ports
  do not deliver enough current for steppers under load).

## 7. Open questions to resolve before implementation

These must be answered, in this order, before any implementation issue
lands:

1. **Live property stream**: today AF data is written to the card. For
   real-time control we need a live channel. Options:
   a. Existing ML USB serial output channel (low rate, may work)
   b. Wi-Fi via existing Canon dummy WFT or ESP32-based bridge
   c. HDMI overlay scraping (last resort)
   No clear winner. Spike this before committing.
2. **Bus observation gap**: the EF-mount observability bound (see
   peer spec) means lens-internal motor state is invisible. Does the
   robotic-optics use case need it? Probably no for external
   telescope/microscope optics (the camera AF chip is doing the
   sensing, not the lens motor). Confirm.
3. **AF chip stability vs astro targets**: Canon AF was trained on
   everyday photo subjects. Does it produce usable focus-intent
   signals on a star field or a microscope sample? Spike on real
   targets before committing.
4. **Coordinate framework**: AF-intent is in image-plane focus
   space. Optical actuators move in step-count space. The mapping is
   lens-/optic-specific. Calibration procedure must be designed.
5. **Failure modes**: what happens when AF hunts on an empty sky? The
   logger sees a hunting pattern (Sprint C4 classifies it). The
   controller must refuse to drive motors during hunting.
6. **Safety**: limit switches, mechanical stops, encoder over-travel
   detection. Non-negotiable; design before any motor wiring.

## 8. What this design does NOT do

- It does not specify a wire protocol. Protocol design follows the live
  property stream decision.
- It does not specify motor controllers. Off-the-shelf vs custom is
  decided per optic.
- It does not propose firmware changes beyond what `af_logger` already
  delivers in Sprint C2.
- It does not modify the Canon mount task or attempt EF-protocol
  patching (see peer spec for the bound).

## 9. Sequencing recommendation

When this work is ready to start (after the current initiative
completes):

1. Live property stream spike (1 week).
2. Coordinate-frame calibration spike on a single lens + telescope
   focuser (1 week).
3. AF-intent stability spike on astro / microscopy targets (1 week).
4. Decide go/no-go for `tools/optics-driver/`.
5. If go: scope a dedicated Linear initiative with hardware budget.

## 10. Closes

- TIN-1231 (this design doc)
- Inputs to a future, separate initiative (not opened today)
