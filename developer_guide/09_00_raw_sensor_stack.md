# 9. Raw and Sensor Stack — Current-State Map

**Source**: Sprint B1 audit (Linear TIN-1221). Read-only survey of the raw /
EDMAC / MLV pipeline in this fork as of 2026-05-16.

**Status**: descriptive snapshot. Line numbers and behavioral claims were
spot-checked but assume a 2026-05-16 tree; re-verify with `grep -n` before
acting on a specific line.

## 9.1 Buffer plumbing: sensor → EDMAC → MLV

The capture pipeline is event-driven and synchronous to liveview vsync.

1. **Per-frame entry point**: `raw_lv_vsync()` at `src/raw.c:2129` runs on
   every liveview vsync. It applies any active per-frame digital gain by
   writing `lv_raw_gain` (`src/raw.c:195`) to `SHAD_GAIN_REGISTER`
   (`0xC0F08030`, `src/raw.c:187`) via `EngDrvOut` at `src/raw.c:2144`.
   This register is **Digic V+ only** (5D3, 5D4); the 5D2 path is
   different (see 9.5).

2. **Raw buffer ingestion**: `raw_lv_request()` and `raw_update_params()`
   configure the EDMAC-fed raw buffer for liveview. The buffer is
   double/ring-buffered with the bayer pattern encoded in
   `raw_info.cfa_pattern` (around `src/raw.c:496`).

3. **`raw_vidx` event push**: when raw video recording is active,
   `modules/raw_video/raw_vidx/event_pusher.c` populates a `raw_vid_event`
   struct at vsync time (around lines 283–405) with frame geometry, crop
   offsets, source pointer, and timestamp. This event is enqueued to the
   worker task.

4. **Worker → file**: `modules/raw_video/raw_vidx/worker.c` (around lines
   242–343) consumes events, attaches per-frame metadata, and writes via
   `FIO_WriteFile()` (around `worker.c:481`).

5. **File-level setup**: `modules/raw_video/mlv_rec/mlv_rec.c` writes the
   one-time MLV headers via `mlv_write_rawi()` and `mlv_write_rawc()`
   (around `mlv_rec.c:2682`–`2683`) and populates the recurring metadata
   block table at start (`mlv_rec.c:2698`).

**Timestamp resolution**: MLV blocks share a 64-bit hardware counter via
`mlv_hdr_t` (`modules/raw_video/mlv_rec/mlv.h:42–48`). This is a
hardware tick, not wall-clock; convert with the per-platform timer
frequency.

## 9.2 MLV block taxonomy

Header structs in `modules/raw_video/mlv_rec/mlv.h`:

| 4-char code | Header struct | Phase | Owner |
|---|---|---|---|
| `MLVI` | `mlv_file_hdr_t` (line 62) | File header (once) | `mlv_rec` |
| `VIDF` | `mlv_vidf_hdr_t` (line 75) | Per video frame | `mlv_rec` / `raw_vidx` |
| `AUDF` | `mlv_audf_hdr_t` (line 84) | Per audio frame | `mlv_snd` |
| `RAWI` | `mlv_rawi_hdr_t` (line 93) | File header (once) | `mlv_rec` |
| `RAWC` | `mlv_rawc_hdr_t` (line 127) | File header (once) | `mlv_rec` |
| `WAVI` | `mlv_wavi_hdr_t` (line 139) | Audio format | `mlv_snd` |
| `EXPO` | `mlv_expo_hdr_t` (line 150) | Cyclic (~1 Hz) | `mlv_rec` |
| `LENS` | `mlv_lens_hdr_t` (line 165) | Cyclic | `mlv_rec` |
| `RTCI` | `mlv_rtci_hdr_t` (line 182) | Cyclic | `mlv_rec` |
| `IDNT` | `mlv_idnt_hdr_t` (line 191) | File header | `mlv_rec` |
| `XREF` | `mlv_xref_hdr_t` (line 207) | Finalization | `mlv_rec` |
| `INFO` | `mlv_info_hdr_t` (line 214) | Optional | `mlv_rec` |
| `DISO` | `mlv_diso_hdr_t` (line 222) | Per dual-ISO frame | `dual_iso` |
| `MARK` | `mlv_mark_hdr_t` (line 229) | Marker | `mlv_rec` |
| `STYL` | `mlv_styl_hdr_t` (line 241) | Style/color | `mlv_rec` |
| `ELVL` | `mlv_elvl_hdr_t` (line 249) | Electronic leveling | `mlv_rec` |
| `WBAL` | `mlv_wbal_hdr_t` (line 262) | Cyclic | `mlv_rec` |
| `DEBG` | `mlv_debg_hdr_t` (line 271) | Debug | various |

The cyclic metadata interval is driven by `MLV_RTCI_BLOCK_INTERVAL` in
`mlv_rec.c` (around lines 1522–1541).

**Gap relevant to Sprint B2 (RAWX)**: no block today carries per-frame
calibration state (analog gain, digital gain, column offset, dark current
temp, DPC/FPN snapshot refs). The cyclic blocks change too slowly for
per-frame calibration; a new per-frame `RAWX` block is the right shape.

## 9.3 Control surfaces

What is reachable from the firmware today, by name:

- **Digital gain (Digic V+)**: `lv_raw_gain` int variable in `src/raw.c`.
  Written into the camera by `EngDrvOut(SHAD_GAIN_REGISTER, ...)` per
  vsync. Readable via `shamem_read(SHAD_GAIN_REGISTER)` (see
  `src/raw.c:1375`).
- **Analog gain / ADTG / CMOS registers**: not directly exposed in
  `src/raw.c`. Reached via per-platform `cmos_iso_t` and `adtg_iso_t`
  tables (per-platform `consts.h`/`internals.h`). Modules like
  `dual_iso`, `crop_rec`, and `raw_twk` write these registers via
  `EngDrvOut`. The names and addresses are platform-specific.
- **Black/white level**: `raw_info.black_level`, `raw_info.white_level`
  (around `src/raw.c:496`). Static per session, computed on init.
- **Dark current temp**: not exposed by `src/raw.c`. Some platforms have
  a sensor temperature property, but it is not threaded into the raw
  pipeline.
- **DPC (defective-pixel correction) tables**: not exposed in the MLV
  stack. Assumed handled at the sensor/preprocessing level upstream of
  EDMAC.
- **FPN (fixed-pattern noise) data**: same.
- **Bayer pattern**: `raw_info.cfa_pattern`, persisted in `RAWI`.

**Inference**: for the planned `RAWX` block, the cleanest emission
context is from `event_pusher.c` (where `raw_vid_event` is built) and
`worker.c` (where it lands in the file), because that thread already has
read access to `raw_info` and the per-frame state. Reaching ADTG/CMOS
registers requires per-platform glue — propose surfacing a small
helper that snapshots a configurable list of registers per platform.

## 9.4 Sensor-mod implications (AA filter removed)

For AA-filter-removed sensors used in spectral / narrowband work:

- The bayer pattern itself does not change — `RAWI` still describes it
  correctly.
- The spatial frequency profile changes: AA-filter-removed sensors have
  energy above the Nyquist limit. The stock demosaic assumption (low-pass
  CFA) breaks down. The host stacker (Sprint B3) must support a
  **skip-demosaic / mosaic-direct mode** for spectral capture, and a
  demosaic with sharper kernels for normal post.
- For narrowband (H-alpha, NIR), the practical Bayer-pattern usage
  changes: red/blue channels carry most signal; green is near-noise.
  This is a host concern, not a firmware concern, but the RAWX block
  should carry enough state to inform the host's choice (the per-frame
  channel that actually saw light is informative).

## 9.5 Per-platform deltas

| Concern | 5D2.212 (Digic IV) | 5D3.113 / 5D3.123 (Digic 5+) | 5D4.133 (Digic 6+) |
|---|---|---|---|
| `RAW_TYPE_REGISTER` | `0xC0F37014` (`src/raw.c:140–180` branch) | `0xC0F08114` | `0xC0F08114` |
| `SHAD_GAIN_REGISTER` digital gain | not exposed | `0xC0F08030`, written per vsync | `0xC0F08030` |
| `lv_raw_gain` post-sensor gain | unavailable | available | available |
| MLV block emission | same | same | same |
| AF system (relevant for AFLG) | older 9-point | 61-point | 61-point + Dual Pixel |

The 5D3.113 and 5D3.123 platforms share most code paths; the `.113` and
`.123` distinguish firmware revisions, not architecture.

## 9.6 Proposed RAWX hook points (for Sprint B2)

Recommended firmware emission path:

1. **Extend** `raw_vid_event` in `modules/raw_video/raw_vidx/event_pusher.c`
   (around line 51) with a `rawx_payload` field carrying snapshots of:
   - `lv_raw_gain` (Digic V+ only; sentinel on 5D2)
   - Sensor temperature property value (when reachable)
   - A platform-provided register snapshot (gain/offset registers from
     `cmos_iso_t`/`adtg_iso_t`)
   - Frame ts (already on `mlv_hdr_t`)
2. **Populate** in `event_pusher.c` around lines 388–405 (the per-vsync
   path), right next to where the frame geometry is captured.
3. **Emit** as a new `RAWX` block from `worker.c` immediately after the
   `VIDF` block for that frame, following the pattern at
   `mlv_rec.c:2682–2683` for `RAWI`/`RAWC`.
4. **Define** `mlv_rawx_hdr_t` in `modules/raw_video/mlv_rec/mlv.h`,
   mirroring the shape of `mlv_rawi_hdr_t` (line 93) but versioned and
   per-frame.

Per-platform register surfacing — propose starting with **5D3.123**:
its `cmos_iso_t` / `adtg_iso_t` tables are the most-exercised in
existing modules (`dual_iso`, `crop_rec`), making the register names
the most reliable. 5D2 and 5D4 follow.

## 9.7 Surprises / flags

- **`lv_raw_gain` is not persisted today.** Anything captured today has
  no trace of the digital gain applied per frame. The `RAWX` block is
  the obvious fix; it is also a forcing function to validate that the
  host stacker correctly inverts the gain when needed (or treats it as
  ADC scale).
- **5D2 has no `SHAD_GAIN_REGISTER` path.** A per-platform RAWX shape is
  necessary; `lv_raw_gain` cannot be a required field across all
  platforms. Use a per-field availability bitmap in the block header.
- **`raw.c` mixes platform branches by `#ifdef`**, not by per-platform
  table indirection in many places. The B2 implementation should not
  blow this up — small targeted hooks, not a refactor.
- **`tcc/` is a vendored Tiny C Compiler** used by ML's runtime module
  loader. RAWX changes that affect ABI may need a pass through it.

## 9.8 Verification before action

When acting on this chapter, re-run the spot checks:

```
grep -n "raw_lv_vsync\|SHAD_GAIN_REGISTER\|lv_raw_gain" src/raw.c
grep -n "mlv_rawi_hdr_t\|mlv_rawc_hdr_t\|MLV_RTCI_BLOCK_INTERVAL" \
  modules/raw_video/mlv_rec/mlv.h modules/raw_video/mlv_rec/mlv_rec.c
ls modules/raw_video/raw_vidx/
```

Line numbers above are from the 2026-05-16 tree.
