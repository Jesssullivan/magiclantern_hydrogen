/*
 * raw_spectral — per-frame calibration metadata (RAWX block emitter)
 *
 * Sprint B2 / TIN-1222. SCAFFOLD ONLY.
 *
 * This file is the entry-point shell for the module. The actual
 * implementation hooks into `raw_vidx` per-frame events and emits the
 * RAWX MLV block defined in modules/raw_video/mlv_rec/mlv.h.
 *
 * Hook points identified by Sprint B1 audit (see
 * developer_guide/09_00_raw_sensor_stack.md):
 *
 *   - src/raw.c: raw_lv_vsync() at line 2129 — per-vsync entry; reads
 *     lv_raw_gain and writes SHAD_GAIN_REGISTER on Digic V+.
 *   - modules/raw_video/raw_vidx/event_pusher.c (around lines 51, 283-405)
 *     — `raw_vid_event` population.
 *   - modules/raw_video/raw_vidx/worker.c (around lines 242-343)
 *     — per-frame block emission point.
 *
 * The next slice of B2 implements:
 *   1. Subscribe via raw_vidx's existing callback path (or add a
 *      lightweight hook in event_pusher.c if needed).
 *   2. Snapshot calibration state at frame VSYNC: analog/digital gain,
 *      column offsets, dark temp, DPC/FPN refs, ns timestamp.
 *   3. Emit mlv_rawx_hdr_t through the existing mlv_rec write path.
 *   4. Per-platform register tables: surface 5D3.123 first
 *      (cmos_iso_t / adtg_iso_t are most exercised in tree).
 */

#include <dryos.h>
#include <module.h>

#include "mlv.h"  /* mlv_rawx_hdr_t lives here */

/* TODO(TIN-1222): wire raw_vidx event subscription */
/* TODO(TIN-1222): snapshot per-frame calibration state */
/* TODO(TIN-1222): emit RAWX block via mlv_rec write path */
/* TODO(TIN-1222): per-platform register surfacing (5D3.123 first) */

static unsigned int raw_spectral_init(void)
{
    /* Scaffold: module loads but does not subscribe yet. */
    return 0;
}

static unsigned int raw_spectral_deinit(void)
{
    return 0;
}

MODULE_INFO_START()
    MODULE_INIT(raw_spectral_init)
    MODULE_DEINIT(raw_spectral_deinit)
MODULE_INFO_END()

MODULE_STRINGS_START()
    MODULE_STRING("Description", "Per-frame calibration metadata (RAWX block emitter)")
    MODULE_STRING("Author", "magiclantern_hydrogen")
    MODULE_STRING("License", "GPL")
    MODULE_STRING("Status", "scaffold - see Linear TIN-1222")
MODULE_STRINGS_END()
