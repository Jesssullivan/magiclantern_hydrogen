# af-log — usage reference

```
af-log <subcommand> FILE.mlv
af-log help
af-log version
```

## Subcommands

### `replay FILE.mlv`

Annotated, line-per-event timeline. Each row shows: timestamp, event
type, affected AF point, focus magnitude, and any
availability-bitmap-gated lens fields (focus_near / focus_far /
focus_pos / focal_length / aperture / AFMA).

```
af-log replay capture.mlv | less
```

### `summary FILE.mlv`

Counts per AFLG event type. Lists totals like:

```
HALF_PRESS       12
FOCUS_DONE        7
FOCUS_DATA       58
AF_POINT_CHANGE   3
AF_AREA_CHANGE    1
APERTURE_CHANGE   2
IS_STATE_CHANGE   0
LENS_DYNAMIC      0
HSP_COUNTDOWN     0
─────────────────
83 AFLG blocks total
```

### `detect FILE.mlv`

Pattern classifier. Reports each detected window with the event indices
that triggered it.

| Pattern | Heuristic |
|---|---|
| `focus_bracket` | 5+ FOCUS_DATA events within a 165 ms window. |
| `tracking_dwell` | AF_POINT_CHANGE then FOCUS_DONE within 50 ms. |
| `hunting` | 5 FOCUS_DATA events with ≥ 4 magnitude reversals. |

Tunable window constants live in `src/detect.zig` in the source tree.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Runtime error (file missing, parse failure, no AFLG blocks) |
| 2 | Argument error |

## Event semantics

`AFLG` blocks are emitted by `aflogger` whenever one of the watched
camera properties changes:

| Event | Source property |
|---|---|
| `HALF_PRESS` | `PROP_HALF_SHUTTER` |
| `FOCUS_DONE` | `PROP_LV_FOCUS_DONE` |
| `FOCUS_DATA` | `PROP_LV_FOCUS_DATA` |
| `AF_POINT_CHANGE` | `PROP_LV_AFFRAME` |
| `AF_AREA_CHANGE` | `PROP_LV_AF_AREA_MODE` |
| `APERTURE_CHANGE` | `PROP_APERTURE` |
| `IS_STATE_CHANGE` | `PROP_LV_LENS_STABILIZE` |
| `LENS_DYNAMIC` | `PROP_LENS_DYNAMIC_DATA` (DIGIC 8+) |
| `HSP_COUNTDOWN` | Synthetic countdown emitted by `aflogger` itself. |

DIGIC 8+ fields and other platform-dependent values are gated by the
`MLV_AFLG_HAS_*` availability bitmap. The CLI honors the bitmap and
prints `--` for unavailable fields.

## Typical workflow

```bash
# 1. Confirm telemetry was captured.
af-log summary lens-test.mlv

# 2. Look at the timeline.
af-log replay lens-test.mlv | less

# 3. Spot AF behaviour patterns.
af-log detect lens-test.mlv
```
