# magiclantern_hydrogen host tools — usage

Two Zig-built host CLIs ship with every release:

- [`raw-stack`](#raw-stack) — MLV decoding, RGGB bayer stats, multi-frame
  stacking, master-dark subtraction, FITS / raw-u16 output.
- [`af-log`](#af-log) — AFLG telemetry replay, summary, classifier-based
  pattern detection.

Both expect MLV files captured by the in-firmware modules `rawspect`
(emits `RAWX` calibration blocks) and `aflogger` (emits `AFLG` AF /
lens / TTL telemetry blocks).

Tarball naming: `<tool>-<TAG>-<os>-<arch>.tar.gz`. Today's shipped
matrix is `x86_64-linux` (static musl) and `aarch64-macos` (native).

---

## raw-stack

### Synopsis

```
raw-stack <subcommand> [args...]
```

### Subcommands

| Subcommand | Purpose |
|---|---|
| `inspect FILE.mlv` | Block-by-block dump of every RAWX / AFLG / RAWI / VIDF block with summary. |
| `info FILE.mlv` | Camera geometry from RAWI (width / height / pitch / frame_size / bits_per_pixel) and per-type block counts. |
| `frames FILE.mlv` | One row per VIDF: frame number, timestamp, size, crop/pan position, frameSpace. |
| `raw-stats FILE.mlv` | Byte-level per-VIDF statistics over the post-frameSpace payload. |
| `pixel-stats FILE.mlv` | Decoded 14-bit pixel statistics per VIDF. |
| `bayer-stats FILE.mlv` | Per-frame + aggregate RGGB plane stats (min/max/mean per channel). |
| `mean-frame IN.mlv [IN2.mlv ...] OUT[.fits\|.bin]` | Per-pixel mean across every VIDF in N inputs. |
| `median-frame IN.mlv [IN2.mlv ...] OUT[.fits\|.bin]` | Per-pixel median across every VIDF. |
| `sigma-stack [--sigma N] [--iters N] IN.mlv [...] OUT[.fits\|.bin]` | Iterative sigma-clipped mean (defaults sigma=3, iters=2). |
| `dark-subtract MASTER_DARK.bin IN.mlv [...] OUT[.fits\|.bin]` | Subtract master dark per pixel, then mean-stack the result. |
| `stack FILE...` | Aggregate RAWX calibration metadata across files. |
| `fixture OUT.mlv [simple\|complex]` | Synthetic MLV generator for tests. |
| `help`, `version` | Standard. |

### Output format

`.fits` or `.fit` → FITS image (single HDU, BITPIX=16, big-endian).
Anything else → raw `u16` little-endian (numpy:
`np.fromfile(path, dtype='<u2').reshape(h, w)`).

### Typical workflow — astro reduction

```bash
# 1. Build a master dark from N dark exposures (lens cap on).
raw-stack median-frame darks/*.mlv master-dark.bin

# 2. Dark-subtract + mean-stack the lights into a reduced FITS.
raw-stack dark-subtract master-dark.bin lights/*.mlv reduced.fits

# 3. (Alternative) Outlier-rejecting stack without a dark.
raw-stack sigma-stack --sigma 2.5 --iters 3 lights/*.mlv reduced-sigma.fits
```

### Typical workflow — spectral

```bash
# Inspect what's in your capture.
raw-stack info capture.mlv          # camera geometry
raw-stack inspect capture.mlv       # full block taxonomy
raw-stack bayer-stats capture.mlv   # per-plane R/G1/G2/B statistics

# Stack without a demosaic pass (true spectral data).
raw-stack mean-frame spectral-*.mlv spectral.fits
```

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Runtime error (file not found, format unsupported, etc.) |
| 2 | Argument error (missing args, unknown subcommand) |

---

## af-log

### Synopsis

```
af-log <subcommand> FILE.mlv
```

### Subcommands

| Subcommand | Purpose |
|---|---|
| `replay FILE.mlv` | Annotated event timeline; availability-bitmap-aware field display. |
| `summary FILE.mlv` | Counts per `AFLG` event type. |
| `detect FILE.mlv` | Pattern classifier: detects `focus_bracket`, `tracking_dwell`, `hunting` windows. |
| `help`, `version` | Standard. |

### Event types emitted by `aflogger`

| Event | Trigger |
|---|---|
| `HALF_PRESS` | Shutter half-press detected via `PROP_HALF_SHUTTER`. |
| `FOCUS_DONE` | AF reports focus achieved. |
| `FOCUS_DATA` | Continuous focus magnitude / position update. |
| `AF_POINT_CHANGE` | AF point selection changed (`PROP_LV_AFFRAME`). |
| `AF_AREA_CHANGE` | AF area-mode changed. |
| `APERTURE_CHANGE` | Aperture command issued (`PROP_APERTURE`). |
| `IS_STATE_CHANGE` | Image-stabilizer state changed (`PROP_LV_LENS_STABILIZE`). |
| `LENS_DYNAMIC` | DIGIC 8+ lens dynamic data update. |
| `HSP_COUNTDOWN` | Half-shutter prediction countdown ticks. |

### Typical workflow

```bash
# What happened in this capture?
af-log summary lens-test.mlv
af-log replay  lens-test.mlv | less

# Did the lens hunt? Did we focus-bracket?
af-log detect  lens-test.mlv
```

### Pattern classifiers

| Classifier | Heuristic |
|---|---|
| `focus_bracket` | 5+ FOCUS_DATA events within a 165 ms window. |
| `tracking_dwell` | AF_POINT_CHANGE followed by FOCUS_DONE within 50 ms. |
| `hunting` | 5 FOCUS_DATA events with ≥ 4 magnitude reversals. |

Tunable windows ship in `tools/af-log/src/detect.zig`.

---

## Reporting issues

File a Linear issue under the `Tinyland` team's `magiclantern_hydrogen`
initiative, or open a GitHub issue at
[Jesssullivan/magiclantern_hydrogen](https://github.com/Jesssullivan/magiclantern_hydrogen/issues).
Include the tool version (`raw-stack version` / `af-log version`), the
MLV file (or a synthetic `fixture` reproduction), and the failing command.
