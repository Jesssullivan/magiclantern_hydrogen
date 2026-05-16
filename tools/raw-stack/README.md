# raw-stack

Host-side raw / spectral reconstruction pipeline for
`magiclantern_hydrogen` MLV captures with `RAWX` calibration metadata.

**Status**: scaffold + RAWX decoder + `inspect` subcommand. Stacker /
demosaic-skip / calibrate subcommands are stubs.
**Linear**: TIN-1223 (Sprint B3).

## Build

From the repo root, inside the dev shell:

```
direnv allow
cd tools/raw-stack
zig build
./zig-out/bin/raw-stack inspect path/to/capture.mlv
```

Or run the tests directly: `zig build test`.

## Subcommands (planned)

| Subcommand | Status | Purpose |
|---|---|---|
| `inspect FILE.mlv` | **implemented** | Stream MLV blocks; print every RAWX and AFLG record; emit summary by block type |
| `stack [opts] FILE...` | stub | Multi-frame stacker with sensor-aware noise model (drizzle + sigma-clip, AA-removed Bayer overrides) |
| `demosaic-skip FILE` | stub | Spectral mode — emit FITS without demosaicing for true spectral data |
| `calibrate KIND DIR` | stub | Build dark / flat / bias frames |

CLI design follows `oauth-mux`-style subcommand dispatch + `--help` /
`--version` short-flags.

## Block formats

Wire layout mirrors `modules/raw_video/mlv_rec/mlv.h`:

- `mlv_rawx_hdr_t` → `Rawx` in `src/mlv.zig`
- `mlv_aflg_hdr_t` → `Aflg` in `src/mlv.zig` (consumed by `tools/af-log`, not raw-stack, but decoded here for `inspect` convenience)

The `_present` bitmap on each record indicates which optional fields
are populated; the rest carry `SENTINEL_*` values defined in `mlv.h`.

## Pairs with

- `modules/raw_spectral/` — firmware-side RAWX emitter (TIN-1222)
- `tools/af-log/` — host CLI for AFLG timelines (TIN-1230)
