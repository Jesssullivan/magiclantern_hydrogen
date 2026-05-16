/*
 * af_logger — AF / lens / TTL telemetry (AFLG block emitter)
 *
 * Sprint C2 / TIN-1228. SCAFFOLD ONLY.
 *
 * Subscribes to Canon AF / lens property IDs (audited in
 * developer_guide/10_00_af_lens_telemetry.md) and emits AFLG MLV blocks
 * per discrete event. Pairs with `modules/raw_spectral` so an imaging
 * capture carries both calibration and AF telemetry in the same MLV
 * stream at the same hardware ticks.
 *
 * The next slice of C2 implements:
 *   1. PROP_HANDLER subscriptions per chapter 10 §10.8:
 *        PROP_HALF_SHUTTER, PROP_LV_FOCUS_DONE, PROP_LV_FOCUS_DATA,
 *        PROP_LV_AFFRAME, PROP_LENS_DYNAMIC_DATA (DIGIC8+ gated),
 *        PROP_APERTURE, PROP_LV_LENS_STABILIZE, PROP_AFPOINT.
 *   2. Per-platform feature gating — 5D3 has no PROP_LENS_DYNAMIC_DATA;
 *      use the AFLG fields_present bitmap to make this explicit.
 *   3. AFLG block emission via the mlv_rec write path. Run the handler
 *      work in a separate task to keep the property handler context
 *      light (existing dot_tune / dual_iso pattern).
 *   4. Lossless half-press -> confirm -> shutter cycle capture.
 *
 * Observability bound: property layer only. No EF-mount bus traffic
 * (see docs/spec/ef-mount-ttl-observation-2026-05-16.md).
 */

#include <dryos.h>
#include <module.h>

#include "mlv.h"  /* mlv_aflg_hdr_t lives here */

/* TODO(TIN-1228): PROP_HANDLER(PROP_HALF_SHUTTER) - emit HALF_PRESS */
/* TODO(TIN-1228): PROP_HANDLER(PROP_LV_FOCUS_DONE) - emit FOCUS_DONE */
/* TODO(TIN-1228): PROP_HANDLER(PROP_LV_FOCUS_DATA) - emit FOCUS_DATA */
/* TODO(TIN-1228): PROP_HANDLER(PROP_AFPOINT) - emit AF_POINT_CHANGE */
/* TODO(TIN-1228): PROP_HANDLER(PROP_LV_AFFRAME) - emit AF_AREA_CHANGE */
/* TODO(TIN-1228): PROP_HANDLER(PROP_APERTURE) - emit APERTURE_CHANGE */
/* TODO(TIN-1228): PROP_HANDLER(PROP_LV_LENS_STABILIZE) - emit IS_STATE_CHANGE */
/* TODO(TIN-1228): PROP_HANDLER(PROP_LENS_DYNAMIC_DATA) - emit LENS_DYNAMIC (DIGIC8+) */
/* TODO(TIN-1228): per-platform feature gating + fields_present bitmap */
/* TODO(TIN-1228): block emission task (offload from property handler context) */

static unsigned int af_logger_init(void)
{
    /* Scaffold: module loads but does not subscribe yet. */
    return 0;
}

static unsigned int af_logger_deinit(void)
{
    return 0;
}

MODULE_INFO_START()
    MODULE_INIT(af_logger_init)
    MODULE_DEINIT(af_logger_deinit)
MODULE_INFO_END()

MODULE_STRINGS_START()
    MODULE_STRING("Description", "AF/lens/TTL telemetry (AFLG block emitter)")
    MODULE_STRING("Author", "magiclantern_hydrogen")
    MODULE_STRING("License", "GPL")
    MODULE_STRING("Status", "scaffold - see Linear TIN-1228")
MODULE_STRINGS_END()
