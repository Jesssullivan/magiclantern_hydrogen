# EF Mount TTL Observation — Observability Bounds and Recommendation

- **Date**: 2026-05-16
- **Status**: design / scoping (no implementation in this initiative)
- **Linear**: TIN-1229 (Sprint C3)
- **Depends on**: `developer_guide/10_00_af_lens_telemetry.md`
- **Feeds**: `docs/spec/robotic-optics-actuation-2026-05-16.md` (Sprint C5)

## 1. Question

Can Magic Lantern firmware, running on the in-scope 5D platforms,
**passively observe** the EF mount's bus traffic between body and lens?
Or is it bounded to the **commanded values** that pass through Canon's
property system?

This question matters because the future robotic-optics workstream
(Sprint C5) needs to decide whether AF / focus / aperture telemetry can
be recorded with the camera body as the only instrument, or whether
external bus-sniffing hardware is a hard prerequisite.

## 2. Method (this spec)

Read-only review of:

- `src/lens.c` (full surface) — every reference to byte-level mount
  communication, raw lens reads, or low-level lens commands.
- `src/property.c` and `src/property.h` — the property registry the
  firmware uses to surface lens state.
- ML forum, dpreview, and public RE corpus references found in code
  comments.
- `developer_guide/10_00_af_lens_telemetry.md` (Sprint C1 output).

No instrumentation, no measurements. This is a current-state map.

## 3. What the firmware already exposes (property layer)

Already documented in chapter 10. Headline:

- `PROP_LENS_NAME`, `PROP_LENS`, `PROP_LENS_STATIC_DATA` — static lens
  identity.
- `PROP_LENS_DYNAMIC_DATA` (**DIGIC8+ only**, i.e. 5D4 yes, 5D3 no) —
  rich per-state telemetry: focus near/far/pos, focal length, IS state,
  physical AF/MF switch state.
- `PROP_LV_FOCUS_DATA` — per-vsync focus magnitude during LiveView AF.
- `PROP_LV_LENS_DRIVE_REMOTE` — focus motor command (we drive it; lens
  responds; confirmation via `PROP_LV_FOCUS_DONE`).
- `PROP_APERTURE` — commanded aperture.

Everything here is "what the body **sent** the lens" or "what the lens
told the body **at the property layer**." It is not the literal byte
stream on the EF pins.

## 4. What the firmware does NOT expose

From code review of `src/lens.c` and `src/property.c`:

- **No byte-level EF mount bus access** is exposed via a property or a
  callable function in firmware. There is no `lens_read_raw_bus()` or
  equivalent symbol.
- **No EDMAC channel carries mount-bus traffic.** AF/lens data flows
  through the Canon-internal task that hydrates the property system; ML
  observes the property layer, not below.
- **No TTL flash metering** properties — `PROP_FLASH_*` are not in the
  property surface used by `lens.c` / `focus.c`.
- **No lens motor current / stall sensing** — `PROP_LV_LENS_DRIVE_REMOTE`
  is a command, not a feedback channel. `PROP_LV_FOCUS_DONE` is a
  binary "done" signal, not a torque or position trace.
- **No raw timing of bus transactions** — the harmonic-mean focus
  distance computation (`lens.c:1974`) and the `0xFFFF` "unknown"
  sentinel (`lens.c:1973`) indicate that even DIGIC8+ lens telemetry is
  a curated, sanitized snapshot, not bus-level data.

## 5. Why this is the bound

Canon's mount-side firmware runs on a dedicated coprocessor (DryOS task
on a separate ARM core in newer bodies) and exposes only the property
surface to the main task that ML hooks into. Reaching below that layer
would require:

- **Patching the Canon mount task**, which would be a major reverse-
  engineering effort and likely fragile across firmware versions. Out
  of scope for this initiative.
- **External hardware sniffing** — a passive bus tap on the EF mount
  pins, recorded externally. This is what is needed for true protocol
  telemetry. Several public RE projects exist (search "EF protocol
  sniffer"); none are in this tree.

## 6. Implications for downstream work

For **Sprint C2 (`af_logger` module)**: the firmware-side logger is
bounded to property-layer telemetry. That is sufficient for a useful
log — most of the user-visible AF/lens behavior is captured. The
`AFLG` block design in chapter 10 reflects this bound.

For **Sprint C5 (robotic-optics design)**: any closed loop that needs
**bus-level** telemetry (e.g. directly observing the lens's reported
focus position before the body's harmonic-mean simplification) must
plan for an **external mount-sniffer device**. The design doc should
make this explicit and not paper over it.

For 5D3 specifically: the missing `PROP_LENS_DYNAMIC_DATA` means we
lose focus-near / focus-far / IS-state / AF-MF-switch. The `AFLG` block
already accommodates this with sentinel values; do not pretend to log
data we cannot reach.

## 7. Recommendation

1. **Build `af_logger` with property-layer telemetry only.** It is
   sufficient for the spectral-imaging and AF-pattern analysis use
   cases described in the plan.
2. **Document the bus-observation gap in the C5 robotic-optics design.**
   If/when future work needs raw EF protocol traces, scope a separate
   hardware spike (external sniffer + host-side decoder).
3. **Do not plan a Canon mount-task patch.** It is high effort,
   high risk, version-fragile, and not on the critical path for any
   in-scope goal.
4. **Cross-reference with public EF protocol RE** when the time comes
   for an external sniffer — the dpreview / ML forum / Roger Clark
   corpus has substantial groundwork. Don't reinvent.

## 8. Open questions (deferred)

- Is there any read-only register or shamem location on the body that
  exposes the lens-side raw responses before they reach the property
  system? `src/raw.c` uses `shamem_read` for graphics registers; a
  parallel surface for lens registers may or may not exist. Worth a
  one-day grep-and-document spike if motivated, but does not block C2.
- How stable is `PROP_LENS_DYNAMIC_DATA` payload across DIGIC8+ firmware
  revisions? The structure layout (`_dynamic->FL`, `st2`, `st3` bit
  meanings) is implementation-defined and could shift with Canon
  firmware updates. Log the firmware version alongside any AFLG capture
  so future-us can disambiguate.

## 9. Closes

- TIN-1229
- Cleared dependency for TIN-1228 (C2 implementation can proceed
  without bus observation)
- Input for TIN-1231 (C5 design)
