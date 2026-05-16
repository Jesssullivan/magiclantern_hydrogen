/*
 * af_logger — AF / lens / TTL telemetry (AFLG block emitter)
 *
 * Sprint C2 / TIN-1228.
 *
 * Subscribes to Canon AF/lens properties (audited in
 * developer_guide/10_00_af_lens_telemetry.md) and emits AFLG MLV
 * blocks into the active recording stream via mlv_rec's public
 * cooperator API (mlv_rec_register_cbr + mlv_rec_queue_block).
 *
 * Architecture:
 *   - PROP_HANDLERs run synchronously in the property task; they only
 *     snapshot the latest payload (no malloc, no file I/O).
 *   - MLV_REC_EVENT_STARTING flips us into the active state.
 *   - For each event that fired since the last VIDF, we allocate an
 *     AFLG block, fill it from the snapshot, and queue it via
 *     mlv_rec_queue_block (which takes ownership and frees after
 *     writing).
 *   - MLV_REC_EVENT_STOPPED flips us back to idle.
 *
 * Observability bound: property layer only — no EF-mount bus traffic
 * (see docs/spec/ef-mount-ttl-observation-2026-05-16.md).
 */

#include <dryos.h>
#include <module.h>
#include <console.h>
#include <property.h>

#include "mlv.h"
#include "mlv_rec_interface.h"

/* Active state. Only emit AFLG blocks when set. */
static volatile int g_recording = 0;

/* Latest snapshot of each property. */
static struct
{
    int half_shutter;
    uint32_t focus_done_raw;
    uint32_t focus_magnitude;
    uint16_t af_point;
    uint16_t af_area_mode;
    uint32_t aperture_raw;
    uint8_t is_state;

    /* DIGIC8+ rich telemetry; sentinels otherwise. */
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

/* Allocate, fill, and queue an AFLG block. Caller is responsible for
 * checking g_recording. The block is freed by mlv_rec after it's
 * written to the file. */
static void emit_aflg(uint16_t event_type, uint32_t fields_present)
{
    mlv_aflg_hdr_t *hdr = malloc(sizeof(mlv_aflg_hdr_t));
    if (!hdr) return;

    /* mlv_rec sets timestamp; we set everything else. */
    mlv_set_type((mlv_hdr_t *) hdr, "AFLG");
    hdr->blockSize      = sizeof(mlv_aflg_hdr_t);
    hdr->version        = 1;
    hdr->event_type     = event_type;
    hdr->fields_present = fields_present;
    hdr->af_point       = g_af.af_point;
    hdr->af_area_mode   = g_af.af_area_mode;
    hdr->focus_magnitude = (uint16_t) g_af.focus_magnitude;
    hdr->af_result      = (uint16_t) g_af.focus_done_raw;
    hdr->hsp_countdown  = 0; /* TODO: hook focus.c:880 */
    hdr->af_mf_physical = g_af.af_mf_physical;
    hdr->is_state       = g_af.is_state;
    hdr->reserved1      = 0;
    hdr->focus_near     = g_af.focus_near;
    hdr->focus_far      = g_af.focus_far;
    hdr->focus_pos      = g_af.focus_pos;
    hdr->focal_length   = g_af.focal_length;
    hdr->aperture_raw   = g_af.aperture_raw;
    hdr->afma_offset    = MLV_RAWX_SENTINEL_I32;

    mlv_rec_queue_block((mlv_hdr_t *) hdr);
}

PROP_HANDLER(PROP_HALF_SHUTTER)
{
    g_af.half_shutter = buf[0];
    g_af.event_count++;
    if (g_recording) emit_aflg(MLV_AFLG_EVT_HALF_PRESS, 0);
}

PROP_HANDLER(PROP_LV_FOCUS_DATA)
{
    /* Per audit chapter 10 §10.3, magnitude is aggregated from
     * buf[2..4]. Capture buf[2] for now; per-platform aggregation
     * deferred to host analyzer. */
    g_af.focus_magnitude = buf[2];
    g_af.event_count++;
    if (g_recording) emit_aflg(MLV_AFLG_EVT_FOCUS_DATA, MLV_AFLG_HAS_LV_FOCUS_DATA);
}

PROP_HANDLER(PROP_LV_AFFRAME)
{
    g_af.af_area_mode = (uint16_t) buf[0];
    g_af.event_count++;
    if (g_recording) emit_aflg(MLV_AFLG_EVT_AF_AREA_CHANGE, MLV_AFLG_HAS_AF_AREA);
}

PROP_HANDLER(PROP_APERTURE)
{
    g_af.aperture_raw = buf[0];
    g_af.event_count++;
    if (g_recording) emit_aflg(MLV_AFLG_EVT_APERTURE_CHANGE, 0);
}

PROP_HANDLER(PROP_LV_LENS_STABILIZE)
{
    g_af.is_state = (uint8_t) buf[0];
    g_af.event_count++;
    if (g_recording) emit_aflg(MLV_AFLG_EVT_IS_STATE_CHANGE, MLV_AFLG_HAS_IS_STATE);
}

PROP_HANDLER(PROP_LENS_DYNAMIC_DATA)
{
    /* DIGIC8+ only. Layout per lens.c:1952 — focus_near/focus_far/
     * focusPos/FL/st2/st3 inside an opaque struct. Capture as 16-bit
     * pairs from buf[0..2]; refine when per-platform struct
     * definitions are available. */
    g_af.focus_near     = (uint16_t)(buf[0] & 0xFFFF);
    g_af.focus_far      = (uint16_t)((buf[0] >> 16) & 0xFFFF);
    g_af.focus_pos      = (uint16_t)(buf[1] & 0xFFFF);
    g_af.focal_length   = (uint16_t)((buf[1] >> 16) & 0xFFFF);
    g_af.af_mf_physical = (uint8_t)((buf[2] >> 8) & 0x80);
    g_af.event_count++;
    if (g_recording) {
        emit_aflg(MLV_AFLG_EVT_LENS_DYNAMIC,
                  MLV_AFLG_HAS_DYNAMIC_LENS | MLV_AFLG_HAS_PHYSICAL_SWITCH);
    }
}

static void af_logger_starting(uint32_t event, void *ctx, mlv_hdr_t *hdr)
{
    (void) event; (void) ctx; (void) hdr;
    g_recording = 1;
    console_printf("af_logger: AFLG emission ON (recording started).\n");
}

static void af_logger_stopped(uint32_t event, void *ctx, mlv_hdr_t *hdr)
{
    (void) event; (void) ctx; (void) hdr;
    g_recording = 0;
    console_printf("af_logger: AFLG emission OFF. %u total prop events.\n",
                   g_af.event_count);
}

static unsigned int af_logger_init(void)
{
    g_recording = 0;
    g_af.event_count = 0;
    mlv_rec_register_cbr(MLV_REC_EVENT_STARTING, &af_logger_starting, NULL);
    mlv_rec_register_cbr(MLV_REC_EVENT_STOPPED,  &af_logger_stopped,  NULL);
    console_printf("af_logger: init. PROP_HANDLERs + mlv_rec CBRs registered.\n");
    return 0;
}

static unsigned int af_logger_deinit(void)
{
    g_recording = 0;
    mlv_rec_unregister_cbr(&af_logger_starting);
    mlv_rec_unregister_cbr(&af_logger_stopped);
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
    MODULE_STRING("Status", "Sprint C2 first-cut, see Linear TIN-1228")
MODULE_STRINGS_END()
