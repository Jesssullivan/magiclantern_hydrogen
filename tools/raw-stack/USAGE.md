# raw-stack — usage reference

```
raw-stack <subcommand> [args...]
raw-stack help
raw-stack version
```

## Subcommands

### `info FILE.mlv`

Print RAWI camera geometry (width, height, pitch, frame_size,
bits_per_pixel) and per-block-type counts (VIDF, RAWX, AFLG).

```
raw-stack info capture.mlv
```

### `inspect FILE.mlv`

Block-by-block dump including decoded RAWX and AFLG fields, ending with
a per-type summary.

### `frames FILE.mlv`

One row per VIDF: frame number, timestamp, size, crop/pan position,
frameSpace.

### `raw-stats FILE.mlv`

Byte-level per-VIDF statistics on the post-frameSpace payload (min, max,
mean) plus aggregate.

### `pixel-stats FILE.mlv`

Decoded 14-bit pixel statistics per VIDF (min, max, mean). Requires
RAWI declaring `bits_per_pixel=14`.

### `bayer-stats FILE.mlv`

Per-frame **and** aggregate RGGB plane stats (R, G1, G2, B with
min / max / mean per channel).

### `mean-frame IN.mlv [IN2.mlv ...] OUT[.fits|.bin]`

Per-pixel arithmetic mean across every VIDF in N input MLVs. Output
format inferred from extension:

- `.fits` / `.fit` → single-HDU FITS, BITPIX=16, big-endian.
- anything else → raw `u16` little-endian.

All inputs must share RAWI width × height.

### `median-frame IN.mlv [IN2.mlv ...] OUT[.fits|.bin]`

Per-pixel median across every VIDF. Robust against cosmic-ray hits and
single-frame hot pixels at the cost of throwing away information from
non-outlier samples.

### `sigma-stack [--sigma N] [--iters N] IN.mlv [IN2.mlv ...] OUT[.fits|.bin]`

Iterative sigma-clipped mean stacker. Per pixel: collect samples,
compute mean + stddev, reject samples > sigma*stddev from mean, repeat
for `iters` iterations, emit final mean.

Defaults: `--sigma 3.0 --iters 2`.

Reports total samples kept versus total samples input — useful for
sanity-checking that you're not clipping the signal.

### `dark-subtract MASTER_DARK.bin IN.mlv [IN2.mlv ...] OUT[.fits|.bin]`

Subtract a master dark frame (a raw `u16` LE file matching the VIDF
pixel count — typically built by `mean-frame` or `median-frame` over
dark exposures) from every VIDF pixel (saturating at 0), then
per-pixel mean the result across all frames. Reports clip counts at
low and high saturation.

### `stack FILE...`

Aggregate RAWX calibration metadata across N input MLVs. Reports
digital-gain min/mean/max and the union of `MLV_RAWX_HAS_*` fields
present.

### `fixture OUT.mlv [simple|complex]`

Write a synthetic MLV containing RAWI + VIDF + RAWX + AFLG blocks for
test fixtures. `complex` appends an AFLG suffix that exercises the
`af-log detect` classifiers.

## Output format conventions

| Extension | Format |
|---|---|
| `.fits`, `.fit` | FITS image: 2880-byte header, BITPIX=16, big-endian. |
| anything else | Raw `u16` little-endian. Numpy: `np.fromfile(p, dtype='<u2').reshape(h, w)`. |

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Runtime error (file missing, format unsupported, dimension mismatch) |
| 2 | Argument error (missing args, unknown subcommand, malformed flag) |

## Workflows

### Astro / LOA stacking

```bash
# 1. Master dark from N dark exposures.
raw-stack median-frame darks/*.mlv master-dark.bin

# 2. Reduce lights against the master dark.
raw-stack dark-subtract master-dark.bin lights/*.mlv reduced.fits

# 3. Or, outlier-rejecting stack without a dark.
raw-stack sigma-stack --sigma 2.5 --iters 3 lights/*.mlv reduced.fits
```

### Spectral capture

```bash
raw-stack info  capture.mlv
raw-stack bayer-stats capture.mlv          # quick QA
raw-stack mean-frame spectral-*.mlv spectral.fits
```

### Quick QA on a fresh capture

```bash
raw-stack info        capture.mlv
raw-stack frames      capture.mlv | head
raw-stack pixel-stats capture.mlv | head
```
