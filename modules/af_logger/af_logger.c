/*
 * af_logger — AF / lens / TTL telemetry (AFLG block emitter)
 *
 * Sprint C2 / TIN-1228.
 *
 * Subscribes to the Canon property system for AF / lens events
 * (audited in developer_guide/10_00_af_lens_telemetry.md) and
 * snapshots event payloads into in-memory state. Each PROP_HANDLER
 * runs synchronously in the property handler task context, so it
 * must stay light — heavy work (file I/O, MLV writes) is deferred to
 * a worker task in a future slice.
 *
 * This first slice:
 *   - registers PROP_HANDLERs for the audit-identified events
 *   - tracks the latest snapshot of each event type
 *   - emits an occasional console line so liveness is visible in
 *     qemu-eos boot smoke tests
 *
 * Next slice (Linear TIN-1228):
 *   - flush task that drains the ring buffer to a sidecar MLV file
 *     (AFLG block per event)
 *   - lossless half-press -> confirm -> shutter cycle capture
 *   - per-platform feature gating (5D3 has no PROP_LENS_DYNAMIC_DATA)
 *
 * Observability bound: property layer only. No EF-mount bus traffic;
 * see docs/spec/ef-mount-ttl-observation-2026-05-16.md.
 */

#include <dryos.h>
#include <module.h>
#include <console.h>
#include <property.h>

#include "mlv.h"

/* Latest snapshot — single field per property, last-write-wins. The
 * eventual flush task will read this atomically and emit AFLG blocks. */
static struct
{
    int half_shutter;
    uint32_t focus_done_raw;
    uint32_t focus_magnitude;
    uint16_t af_point;
    uint16_t af_area_mode;
    uint16_t aperture_raw;
    uint8_t is_state;

    /* DIGIC8+ rich telemetry — 5D4 yes, 5D3 sentinels. */
    uint16_t focus_near;
    uint16_t focus_far;
    uint16_t focus_pos;
    uint16_t focal_length;
    uint8_t af_mf_physical;

    uint32_t event_count;
} g_af = {
    .focus_near    = MLV_RAWX_SENTINEL_U16,
    .focus_far     = MLV_RAWX_SENTINEL_U16,
    .focus_pos     = MLV_RAWX_SENTINEL_U16,
    .focal_length  = MLV_RAWX_SENTINEL_U16,
};

PROP_HANDLER(PROP_HALF_SHUTTER)
{
    g_af.half_shutter = buf[0];
    g_af.event_count++;
}

PROP_HANDLER(PROP_LV_FOCUS_DATA)
{
    /* Per audit chapter 10 §10.3, magnitude is aggregated from
     * buf[2..4]. Per-platform exact aggregation differs; capture the
     * raw words for now and defer aggregation to the consumer. */
    g_af.focus_magnitude = buf[2];
    g_af.event_count++;
}

PROP_HANDLER(PROP_LV_AFFRAME)
{
    g_af.af_area_mode = (uint16_t) buf[0];
    g_af.event_count++;
}

PROP_HANDLER(PROP_APERTURE)
{
    g_af.aperture_raw = (uint16_t) buf[0];
    g_af.event_count++;
}

PROP_HANDLER(PROP_LV_LENS_STABILIZE)
{
    g_af.is_state = (uint8_t) buf[0];
    g_af.event_count++;
}

PROP_HANDLER(PROP_LENS_DYNAMIC_DATA)
{
    /* DIGIC8+ only. On 5D3 this handler will not fire. Layout per
     * lens.c:1952 — focus_near/focus_far/focusPos/FL/st2/st3 inside
     * an opaque struct. Capture raw words now; refine when we have
     * matching struct definitions per platform. */
    g_af.focus_near    = (uint16_t)(buf[0] & 0xFFFF);
    g_af.focus_far     = (uint16_t)((buf[0] >> 16) & 0xFFFF);
    g_af.focus_pos     = (uint16_t)(buf[1] & 0xFFFF);
    g_af.focal_length  = (uint16_t)((buf[1] >> 16) & 0xFFFF);
    g_af.af_mf_physical = (uint8_t)((buf[2] >> 8) & 0x80);
    g_af.event_count++;
}

static unsigned int af_logger_init(void)
{
    g_af.event_count = 0;
    console_printf("af_logger: init (scaffold). PROP_HANDLERs registered for "
                   "HALF_SHUTTER / LV_FOCUS_DATA / LV_AFFRAME / APERTURE / "
                   "LV_LENS_STABILIZE / LENS_DYNAMIC_DATA.\n");
    return 0;
}

static unsigned int af_logger_deinit(void)
{
    console_printf("af_logger: deinit. observed %u property events.\n",
                   g_af.event_count);
    return 0;
}

MODULE_INFO_START()
    MODULE_INIT(af_logger_init)
    MODULE_DEINIT(af_logger_deinit)
MODULE_INFO_END()

MODULE_PROPHANDLERS_START()
    MODULE_PROPHANDLER(PROP_HALF_SHUTTER)
    MODULE_PROPHANDLER(PROP_LV_FOCUS_DATA)
    MODULE_PROPHANDLER(PROP_LV_AFFRAME)
    MODULE_PROPHANDLER(PROP_APERTURE)
    MODULE_PROPHANDLER(PROP_LV_LENS_STABILIZE)
    MODULE_PROPHANDLER(PROP_LENS_DYNAMIC_DATA)
MODULE_PROPHANDLERS_END()

MODULE_STRINGS_START()
    MODULE_STRING("Description", "AF/lens/TTL telemetry (AFLG block emitter)")
    MODULE_STRING("Author", "magiclantern_hydrogen")
    MODULE_STRING("License", "GPL")
    MODULE_STRING("Status", "scaffold - see Linear TIN-1228")
MODULE_STRINGS_END()
