# Changelog

All notable changes to `magiclantern_hydrogen` — research fork of Magic
Lantern for spectral / astro imaging on heavily-modified Canon DSLRs.

This fork descends from `reticulatedpines/magiclantern_simplified`; commits
prior to v0.1.0 are inherited from upstream and not enumerated here. See
that repo's history for upstream Magic Lantern development.

## [0.3.0] - 2026-05-17

Outlier-rejection + calibration stacking primitives. Builds on the v0.2.0
pixel-decoding stack with the two operations that turn a sequence of
captures into a research-grade reduced frame: master-dark subtraction
and iterative sigma-clipped mean stacking. Together with the existing
`mean-frame` / `median-frame`, this covers the four main per-pixel
reduction modes used in spectral / astro workflows on modified Canon
sensors.

### Added — raw-stack subcommands

- `dark-subtract DARK IN.mlv [IN2.mlv ...] OUT[.fits|.bin]` — subtract a
  master dark frame (raw u16 LE, typically the output of `mean-frame` or
  `median-frame` over a set of dark exposures) from every VIDF pixel,
  then per-pixel-mean the result across all frames. Clamps to [0, 16383]
  and reports per-extreme clip counts.
- `sigma-stack [--sigma N] [--iters N] IN.mlv [IN2.mlv ...] OUT` —
  iterative sigma-clipped mean stacker. Per pixel: collect samples,
  compute mean + stddev, reject samples >sigma*stddev from mean, repeat
  for `iters` iterations, emit final mean. Defaults: sigma=3.0, iters=2.
  Robust to transient outliers (cosmic rays, sensor glitches) without
  the information loss of pure median. Reports total samples kept vs
  total samples input.

### Added — raw-stack internals

- `sigmaClipMean` helper with unit tests covering: single-outlier
  rejection at sigma=2.0, no-rejection within sigma=3.0 of a tight
  cluster, empty input safety.

### CI

- `scripts/integration-test-zig-tools.sh` now also exercises
  `dark-subtract` (raw + FITS output) and `sigma-stack` (default
  parameters + `--sigma 1.5 --iters 3`).

## [0.2.0] - 2026-05-17

Raw pixel decoding stack: the first sub-version where `raw-stack` can
read real ML captures end to end (RAWI metadata → 14-bit pixel
unpacking → bayer plane decomposition → multi-frame mean/median →
FITS / raw u16 output). Foundation for actual spectral / astro
research workflows on the in-scope 5D platforms.

### Added — raw-stack subcommands

- `info FILE.mlv` — print RAWI camera geometry (width/height/pitch/
  frame_size/bits_per_pixel) + per-type block counts.
- `frames FILE.mlv` — list every VIDF block with frame number,
  timestamp, size, crop/pan position, frameSpace.
- `raw-stats FILE.mlv` — per-VIDF byte-level payload statistics.
- `pixel-stats FILE.mlv` — per-VIDF decoded-pixel statistics
  (requires 14-bit RAWI).
- `bayer-stats FILE.mlv` — per-frame and aggregate R/G1/G2/B plane
  stats (min/max/mean per channel).
- `mean-frame IN.mlv [IN2.mlv ...] OUT[.fits|.bin]` — per-pixel
  running mean across all decoded VIDF frames from N input MLVs.
  Output: FITS (single HDU, BITPIX=16) or raw u16 little-endian
  (extension-inferred).
- `median-frame IN.mlv [IN2.mlv ...] OUT[.fits|.bin]` — per-pixel
  median across decoded frames; robust to hot pixels / cosmic ray hits.

### Added — raw-stack internals

- `mlv.zig`: `Rawi` partial decoder (xRes/yRes + width/height/pitch/
  frame_size/bits_per_pixel from embedded raw_info_t). `Vidf` decoder
  + `readVidfWithPayload` exposing the raw post-frameSpace bytes.
- `pixels.zig`: bit-exact 14-bit packed bayer codec matching ML's
  `struct raw_pixblock` (8 pixels per 14 bytes, GCC ARM bitfield
  order). Pack and unpack with round-trip unit tests covering
  adversarial bit patterns.
- `bayer.zig`: RGGB plane decomposition (`planeOf(x, y)`,
  `summarize(pixels, w, h)`) with per-plane min/max/sum/mean.
- `fits.zig`: minimal FITS image writer — 2880-byte header block
  (SIMPLE/BITPIX/NAXIS/NAXIS1/NAXIS2/BZERO/BSCALE/OBJECT/ORIGIN/
  COMMENT/END), big-endian int16 data, padded to 2880-byte boundary.
- `fixture.zig`: now emits a RAWI block first with dimensions derived
  from actual VIDF payload size; VIDF payload (default 112 bytes =
  8 raw_pixblocks = 64 pixels) is deterministic so all downstream
  subcommands can be asserted in CI.

### Fixed

- Release workflow stage step now per-platform-names firmware
  artifacts (v0.1.0 only shipped one file because the loop used
  last-platform-wins overwriting).

### CI

- `scripts/integration-test-zig-tools.sh` now exercises:
  fixture → inspect → replay → summary → detect → info → frames →
  raw-stats → pixel-stats → bayer-stats → mean-frame (raw + FITS) →
  median-frame.

### Operator

- `just bootstrap-qemu-eos` and a meaningfully diagnostic
  `just qemu-test` recipe — wires the path for TIN-1217 without
  requiring the sibling repo to be present.

## [0.1.0] - 2026-05-16

First release. Establishes the modern development substrate, lands the
foundational documentation, and ships first-cut firmware modules and
host-side tooling. All CI jobs green on Linux.

### Workstream A — Standards & Infrastructure

- `AGENTS.md` + `CLAUDE.md` source-of-truth contracts (cross-constellation house style: direnv → nix devShell → Justfile SSOT → bzlmod Bazel → Flywheel attic).
- Hermetic dev shell via `flake.nix`: `gcc-arm-embedded` 12.3, `nixpkgs#zig_0_14` (0.14.1), `python3` + `docutils`, `lua5.1`, `qemu`, `treefmt`, `git-cliff`, `git-filter-repo`, `git-lfs`, `bazelisk`, `pre-commit`, `just`.
- `Justfile` SSOT with 25 recipes: `build`, `build-all`, `qemu-test`, `fmt`, `lint`, `cache-contract`, `bazel-build-cached`, `mlv-decode`, `af-log-replay`, `push`, `push-clean`, `release`, …
- `MODULE.bazel` + bzlmod scaffold (host tooling only; firmware build stays Make-based).
- `.bazelrc` with `--enable_bzlmod` and ci-cached / executor-backed configs.
- `treefmt.toml` (narrow scope: alejandra on `flake.nix`, taplo on `*.toml`, zig fmt on `tools/**/*.zig`).
- `cliff.toml` for conventional-commits CHANGELOG generation.
- `renovate.json5` for dep automation.
- `.clang-format` mirroring `doc/CODING_STYLE` (Allman, 4-space, 80-col).
- `.gitattributes` LF normalization + binary markers.
- `.pre-commit-config.yaml` wrapping `just fmt-check` + `just lint`.
- `scripts/bazel-cache-backed.sh` + `scripts/cache-attachment-contract.sh` ported from `GloriousFlywheel` (cache-first contract).
- `scripts/integration-test-zig-tools.sh` round-trip fixture validation for CI.
- `.github/workflows/`: `ci.yml`, `qemu-matrix.yml`, `release.yml`, `renovate-pin.yml`.
- Git hygiene: `git filter-repo` dropped orphan toolchain directories (`src/libs/arm-elf-*`, `src/libs/arm-none-eabi-O3-fPIC`) and historical-only binaries (`*.fir`, `ROM0.map`); pack size 239 → 297 MiB after subsequent rewrites (net of multiple LFS migrate / revert iterations).
- `just push` + `just push-clean`: API-mediated workflow for force-updating `origin/dev` past the server-side push ruleset (`gh api PATCH /repos/.../git/refs/heads/dev`).
- Python 3.12 compat fix: `modules/readme2modulestrings.py` uses `shutil.which` instead of removed `distutils.spawn.find_executable`.
- `modules/last_change_info.sh` ported from Mercurial template to git log.

### Workstream B — Raw / Sensor Stack for Spectral Capture

- `developer_guide/09_00_raw_sensor_stack.md`: read-only audit of `src/raw.c`, `edmac`, `modules/raw_video/raw_vidx/`, `modules/raw_video/mlv_rec/`, per-platform CMOS/ADTG tables. Line:line citations.
- `mlv_rawx_hdr_t` block definition in `modules/raw_video/mlv_rec/mlv.h` with availability bitmap (`MLV_RAWX_HAS_*`) and sentinel constants. Carries analog gain, digital gain, column offset, dark current, DPC / FPN refs, ns exposure timestamp.
- `modules/rawspect/` (in-firmware): registers `CBR_VSYNC` (snapshots `SHAD_GAIN_REGISTER` on Digic V+ per liveview frame) and `CBR_RAW_INFO_UPDATE`. Hooks `mlv_rec_register_cbr(MLV_REC_EVENT_VIDF, ...)` and allocates + queues a `RAWX` block paired with every `VIDF`. Builds for all four in-scope platforms.
- `tools/raw-stack/` (host CLI, Zig 0.14):
  - `inspect FILE.mlv` — full RAWX + AFLG decoder; per-block printout + summary by type.
  - `fixture OUT.mlv [simple|complex]` — synthetic generator covering all detect classifiers.
  - `stack FILE...` — multi-file RAWX metadata aggregator (digital gain min / mean / max; fields_present union).
  - `demosaic-skip` and `calibrate` stubbed for future slice.
  - Unit tests round-trip the wire format; integration test asserts end-to-end via `scripts/integration-test-zig-tools.sh`.

### Workstream C — AF / Lens / TTL Telemetry

- `developer_guide/10_00_af_lens_telemetry.md`: read-only audit of `src/focus.c`, `src/lens.c`, `src/property.c` + property IDs. Confirmed `PROP_HALF_SHUTTER`, `PROP_LV_FOCUS_DONE`, `PROP_LV_FOCUS_DATA`, `PROP_LV_AFFRAME`, `PROP_APERTURE`, `PROP_LV_LENS_STABILIZE`, `PROP_LENS_DYNAMIC_DATA` (DIGIC8+), `PROP_AFMA` (5D3). Per-platform AF chip deltas (5D3 vs 5D4 + Dual Pixel).
- `mlv_aflg_hdr_t` block definition + `mlv_aflg_event_t` enum (HALF_PRESS, FOCUS_DONE, FOCUS_DATA, AF_POINT_CHANGE, AF_AREA_CHANGE, APERTURE_CHANGE, IS_STATE_CHANGE, LENS_DYNAMIC, HSP_COUNTDOWN). DIGIC8+-only fields gated by availability bitmap.
- `modules/aflogger/` (in-firmware): `PROP_HANDLER`s for the six audited property IDs. Allocates + queues an `AFLG` block per event when recording is active. State tracked via `MLV_REC_EVENT_STARTING` / `STOPPED` cooperator CBRs.
- `tools/af-log/` (host CLI, Zig 0.14):
  - `replay FILE.mlv` — annotated event timeline with availability-bitmap-aware field display.
  - `summary FILE.mlv` — counts per event type.
  - `detect FILE.mlv` — pattern classifier with `focus_bracket` / `tracking_dwell` / `hunting` detectors (tunable windows).
  - Unit tests for each classifier on synthetic event streams.
- `docs/spec/ef-mount-ttl-observation-2026-05-16.md`: observability bound — ML can observe property-layer telemetry only, not raw EF bus traffic.
- `docs/spec/robotic-optics-actuation-2026-05-16.md`: forward-looking design (marked **do not implement**) for stepper/servo actuation of telescope/microscope optics keyed off logged AF intents.

### CI

All nine jobs green on Linux (ubuntu-latest):

- `fmt-and-lint`
- `cache-contract`
- `zig-tools (raw-stack)`, `zig-tools (af-log)`
- `zig-tools-integration` (fixture → inspect → replay → summary → detect)
- `build-firmware` for `5D2.212`, `5D3.113`, `5D3.123`, `5D4.133`

### Known limitations

- **macOS local builds** of the Zig tools fail at the linker stage because nixpkgs `zig` (any version) doesn't currently include the Darwin SDK 26.5 plumbing. Linux CI is unaffected. Tracked under Linear TIN-1241.
- **GitHub LFS** is unusable on this repo because it's still classified as a fork of `reticulatedpines/magiclantern_simplified` and GitHub denies LFS uploads to forks. `data/vram/xy.tiff` survives as a 132-byte LFS pointer (firmware build doesn't read it). Detach via GitHub Settings → Leave fork network to re-enable.
- **qemu-eos integration** is not yet wired into `just qemu-test`. Tracked under Linear TIN-1217. Until then, runtime validation of `rawspect` / `aflogger` is gated.
- **Flywheel attic cache** credentials (`ATTIC_PUBLIC_KEY` repo secret + `ATTIC_SERVER`/`ATTIC_CACHE` repo variables) not yet configured. CI runs without cache attachment.
- **Selective Zig port of hot firmware modules** (B5: mlv writer, dng writer, dual-iso blend) deferred until qemu-eos validation is available.
