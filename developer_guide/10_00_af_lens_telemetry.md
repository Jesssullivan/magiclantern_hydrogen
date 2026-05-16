# 10. AF / Lens / TTL Telemetry — Current-State Map

**Source**: Sprint C1 audit (Linear TIN-1227). Read-only survey of the
AF, lens, and TTL telemetry surface in this fork as of 2026-05-16.

**Status**: descriptive snapshot. Property IDs are mostly confirmed
against `src/property.h`; a few subscription points are inferred from
naming and marked. Line numbers and IDs were spot-checked but
re-verify with `grep -n` before acting on a specific claim.

## 10.1 The two AF systems

Two parallel AF stacks coexist:

- **Photo-mode AF** (mirror-down): driven by `PROP_AF_MODE` /
  `PROP_AFPOINT`. Older surface, broad platform support.
- **LiveView AF** (mirror-up): driven by `PROP_LVAF_MODE` /
  `PROP_LV_FOCUS_*` family. Per-platform behavior varies; 5D4 also has
  Dual Pixel AF on top.

A new `af_logger` module (Sprint C2) must subscribe to **both** to
capture the full half-press → confirm → shutter cycle on any in-scope
platform.

## 10.2 Property ID map

Confirmed IDs from `src/property.h` (line numbers where cited):

| Concern | Property | Confirmed? |
|---|---|---|
| Half-press / shutter-half | `PROP_HALF_SHUTTER` `0x8005000a` | yes (`src/property.h:109`) |
| Photo-mode AF mode | `PROP_AF_MODE` `0x80000004` | confirmed in property.h |
| Photo-mode AF point | `PROP_AFPOINT` `0x8000000A` | confirmed |
| LiveView AF mode | `PROP_LVAF_MODE` `0x80000050` | confirmed |
| LiveView focus state | `PROP_LV_FOCUS` `0x80050001` | confirmed |
| LiveView AF frame/area | `PROP_LV_AFFRAME` `0x80050007` | confirmed |
| LiveView focus data | `PROP_LV_FOCUS_DATA` `0x80050026` | confirmed |
| LiveView focus status | `PROP_LV_FOCUS_STATUS` `0x80050023` | confirmed |
| LiveView focus done | `PROP_LV_FOCUS_DONE` | **inferred** from `focus.c:832`, `lens.c:683` |
| LiveView AF result | `PROP_LV_AF_RESULT` `0x80050029` | confirmed |
| Aperture commanded | `PROP_APERTURE` `0x80000006` | confirmed (`lens.c:1631`) |
| Lens name | `PROP_LENS_NAME` `0x80030021` | confirmed (`lens.c:1397`) |
| Lens static data | `PROP_LENS_STATIC_DATA` `0x8003009a` | confirmed (`lens.c:1361`) |
| Lens dynamic data (DIGIC8+) | `PROP_LENS_DYNAMIC_DATA` `0x80020037` | confirmed (`lens.c:1952`) |
| LV lens info | `PROP_LV_LENS` (`lens.c:1900`) | confirmed via handler |
| LV lens (D67 variant) | `PROP_LV_LENS_D67` (`lens.c:1922`) | confirmed via handler |
| IS state | `PROP_LV_LENS_STABILIZE` `0x8005000e` | confirmed (`lens.c:1461`) |
| Focus motor drive | `PROP_LV_LENS_DRIVE_REMOTE` `0x80050021` | confirmed (`lens.c:808`, `820`, `846`) |
| Remote shutter-half | `PROP_REMOTE_SW1` `0x02050001` | `property.c:438` |
| Remote shutter-full | `PROP_REMOTE_SW2` `0x02050002` | `property.c:438` |
| Remote AF start | `PROP_REMOTE_AFSTART_BUTTON` `0x02050010` | `property.c:438` |
| AF micro-adjust (5D3) | `PROP_AFMA` `0x80040027` | confirmed (`platform/5D3.123/afma.h:3`) |

Inferred IDs (verify before acting):

- `PROP_LV_FOCUS_DONE` — handler-only reference; ID not in
  `src/property.h` window we read. Likely `0x80050024`.
- `PROP_LV_LENS` — handler-only reference; ID likely `0x80050025`.
- `PROP_LV_LENS_D67` — handler-only reference; ID likely `0x80030016`.

## 10.3 Event hook surfaces

`PROP_HANDLER(...)` macro defines a synchronous callback that runs when
the named property changes. Existing subscriptions relevant to a logger:

`src/focus.c`:

| Line | Handler | Purpose |
|---|---|---|
| 832 | `PROP_HANDLER(PROP_LV_FOCUS_DONE)` | AF cycle complete; `buf[0]` is the focus-done state |
| 872 | `PROP_HANDLER(PROP_HALF_SHUTTER)` | half-press transition; sets `hsp_countdown = 3` (line 880) for timing |
| 1001 | `PROP_HANDLER(PROP_LV_FOCUS_DATA)` | per-vsync focus magnitude; `buf[2]`, `buf[3]`, `buf[4]` |

`src/lens.c`:

| Line | Handler | Purpose |
|---|---|---|
| 683 | `PROP_HANDLER( PROP_LV_FOCUS_DONE )` | confirmation handshake for motor commands |
| 1361 | `PROP_HANDLER( PROP_LENS_STATIC_DATA )` | "those are not RAW values! RAW available in PROP_LENS_DYNAMIC_DATA" |
| 1397 | `PROP_HANDLER( PROP_LENS_NAME )` | lens identification |
| 1404 | `PROP_HANDLER( PROP_LENS )` | broader lens info |
| 1461 | `PROP_HANDLER( PROP_LV_LENS_STABILIZE )` | IS state |
| 1631 | `PROP_HANDLER( PROP_APERTURE )` | aperture commanded value |
| 1900 | `PROP_HANDLER( PROP_LV_LENS )` | LV lens info |
| 1922 | `PROP_HANDLER( PROP_LV_LENS_D67 )` | DIGIC 6/7 variant (note name) |
| 1952 | `PROP_HANDLER( PROP_LENS_DYNAMIC_DATA )` | DIGIC8+ rich telemetry: near/far/focus_pos/IS/AF-MF switch |

`src/property.c:438–447`: batch registrations for `PROP_REMOTE_SW1`,
`PROP_REMOTE_SW2`, `PROP_LV_LENS_DRIVE_REMOTE`,
`PROP_REMOTE_AFSTART_BUTTON`, `PROP_LV_AF_RESULT`.

**Subscription pattern for a new module**:

```c
PROP_HANDLER(PROP_HALF_SHUTTER)
{
    /* runs synchronously in the property handler task context.
     * Keep work minimal; do file I/O from a separate task. */
}
```

The `dot_tune` and `dual_iso` modules are existing references for the
"subscribe to property, queue work, return fast" pattern.

## 10.4 EDMAC / DMA paths for AF data

There is no evidence of dedicated EDMAC channels for AF telemetry. AF
data flows through the property system, which is in turn populated by
Canon's internal tasks. From an `af_logger` perspective this is a
property subscription problem, not an EDMAC problem.

Focus motor commands have a specific shape worth knowing:

- Asynchronous: `prop_request_change(PROP_LV_LENS_DRIVE_REMOTE,
  &cmd, 4)` at `lens.c:808`, `846`.
- Synchronous: `prop_request_change_wait(PROP_LV_LENS_DRIVE_REMOTE,
  &cmd, 4, 1000)` at `lens.c:820`, with confirmation via
  `PROP_LV_FOCUS_DONE`.
- Maximum **3 concurrent focus requests** before blocking (`lens.c:846`).

## 10.5 Lens-mount / TTL observability bounds

Observable from firmware today (commanded values, lens-side telemetry):

- Focus near / far / current — `PROP_LENS_DYNAMIC_DATA` on **DIGIC8+
  only** (5D4 yes, 5D3 no).
- Focal length — `PROP_LENS_DYNAMIC_DATA._dynamic->FL`.
- IS state — `PROP_LENS_DYNAMIC_DATA._dynamic->st3 & 0xF` or
  `PROP_LV_LENS_STABILIZE`.
- Physical AF/MF switch — `PROP_LENS_DYNAMIC_DATA._dynamic->st2 & 0x80`
  (`lens.c:1981`). Note: firmware **can fake** `PROP_AF_MODE`; the
  physical switch is the ground truth.
- Aperture commanded — `PROP_APERTURE`.
- AFMA (per-lens AF micro-adjust) on 5D3 — `PROP_AFMA`.

Not observable from firmware today:

- Raw EF-mount electrical protocol / TTL bus traffic. No code evidence
  of byte-level mount communication; no passive bus observation.
- Lens-internal focus motor current / stall detection.
- TTL flash metering data. No PROP_* references for flash TTL.
- Focus speed / acceleration curves (only start/end snapshots).

**Implication for Sprint C3 (TTL observation)**: passive EF-mount
observation is **not** available through the property system. Achieving
it requires either Canon SDK access (not available) or external hardware
bus sniffing. Document this as the bound, not as a gap to fix in
firmware.

## 10.6 Focus distance computation

`lens.c:1974`:

```
focus_distance = (2 * focus_near * focus_far) / (focus_near + focus_far)
```

This is the **harmonic mean** of the near/far bounds, not a linear
average. A logger that reports a single "focus distance" is reporting
the harmonic mean. The AFLG block should carry **both** near and far,
not just the derived distance, so the host analyzer can reproduce the
harmonic mean and detect edge cases.

`focus_pos == 0xFFFF` is the "unknown" sentinel; firmware falls back to
the computed harmonic mean in that case (`lens.c:1973`).

## 10.7 Per-platform deltas (5D3 vs 5D4)

| Concern | 5D3.113 / 5D3.123 | 5D4.133 |
|---|---|---|
| AF chip | dedicated, 61-point | 61-point + Dual Pixel AF |
| `PROP_LENS_DYNAMIC_DATA` | not present | available |
| `PROP_AFMA` | available | not referenced in 5D4 consts |
| Per-platform AF tables | `platform/5D3.123/afma.h` | (verify under `platform/5D4.133/`) |

5D2 is older and has a different AF system again (Digic IV); for now
defer detailed 5D2 mapping until C2 begins.

## 10.8 Proposed AFLG hook points (for Sprint C2)

Recommended subscription set for `modules/af_logger/`:

1. `PROP_HANDLER(PROP_HALF_SHUTTER)` — log start of cycle, snapshot
   timestamp, capture `hsp_countdown` initial value.
2. `PROP_HANDLER(PROP_LV_FOCUS_DONE)` — log completion, `buf[0]` state.
3. `PROP_HANDLER(PROP_LV_FOCUS_DATA)` — log continuous focus magnitude
   (the per-vsync stream).
4. `PROP_HANDLER(PROP_LV_AFFRAME)` — log AF area mode changes (lens
   AF area selection).
5. `PROP_HANDLER(PROP_LENS_DYNAMIC_DATA)` — log lens telemetry on 5D4
   (gate by platform feature check; 5D3 will have empty fields).
6. `PROP_HANDLER(PROP_APERTURE)` — log aperture commands.
7. `PROP_HANDLER(PROP_LV_LENS_STABILIZE)` — log IS state changes.
8. `PROP_HANDLER(PROP_AFPOINT)` — log AF point selection (verify the
   subscription works in LV mode; may need both `PROP_AFPOINT` and
   `PROP_LV_AFFRAME`).

**Proposed `AFLG` payload** (mirror MLV block conventions, versioned
header, per-field availability bitmap):

```c
typedef struct
{
    mlv_hdr_t   hdr;
    uint16_t    af_event_type;     /* enum: half_press, focus_done, ... */
    uint8_t     platform_caps;     /* bitfield: dynamic_data, afma, ... */
    uint8_t     reserved;
    uint16_t    af_point;
    uint16_t    af_area_mode;
    uint16_t    focus_near;        /* DIGIC8+; 0xFFFF if unavailable */
    uint16_t    focus_far;
    uint16_t    focus_pos;
    uint16_t    focal_length;
    uint8_t     is_state;
    uint8_t     af_mf_switch;
    uint16_t    focus_magnitude;   /* from PROP_LV_FOCUS_DATA */
    uint32_t    aperture_raw;
    /* ... versioned; pad to alignment */
} mlv_aflg_hdr_t;
```

Emit alongside `RAWX` (Sprint B2) so a single MLV capture carries both
imaging and AF telemetry at the same hardware ticks.

## 10.9 Surprises / flags

- **`PROP_LV_FOCUS_STATUS` arrives too late for shutter gating**
  (`src/shoot.c:2192` flagged in audit). Use `PROP_LV_FOCUS_DONE` as the
  completion signal instead.
- **Focus motor command queue depth is 3**. A logger that floods
  `PROP_LV_LENS_DRIVE_REMOTE` will see commands serialize, not drop.
  Important for any future motor-control loop reading the log back.
- **Firmware can fake `PROP_AF_MODE`**. The lens hardware AF/MF switch
  is the ground truth (`lens.c:1981`). Always log both.
- **5D3 has no `PROP_LENS_DYNAMIC_DATA`**. The AFLG block must be
  shaped so 5D3 captures with empty dynamic-data fields are valid and
  not confused with "data dropped" cases.
- **No TTL bus visibility from firmware.** Document this clearly in the
  Sprint C5 robotic-optics design — any optic actuation loop that wants
  raw mount telemetry needs external sniffing hardware.
- **Timer tick duration is platform-specific**. The `hsp_countdown =
  3` constraint (`focus.c:880`) is in ticks. Pin the tick frequency per
  platform in the AFLG block header.

## 10.10 Verification before action

When acting on this chapter, re-run the spot checks:

```
grep -n "PROP_HANDLER" src/focus.c src/lens.c | head -30
grep -n "PROP_HALF_SHUTTER\|PROP_LV_FOCUS_DONE\|PROP_LENS_DYNAMIC_DATA" \
  src/property.h
grep -n "PROP_AFMA\|afma" platform/5D3.123/afma.h
```

Line numbers and IDs above are from the 2026-05-16 tree.
