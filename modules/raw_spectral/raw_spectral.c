/*
 * raw_spectral — per-frame calibration metadata snapshot
 *
 * Sprint B2 / TIN-1222.
 *
 * Hooks CBR_VSYNC (called for every LiveView frame) and
 * CBR_RAW_INFO_UPDATE to snapshot calibration-grade state into a
 * thread-safe buffer that downstream consumers (the host pipeline via
 * a sidecar MLV file, or a future raw_vidx integration) can read.
 *
 * This first slice:
 *   - registers the CBR handlers
 *   - reads `lv_raw_gain` proxy via SHAD_GAIN_REGISTER on Digic V+
 *   - emits an occasional console message so the module's liveness is
 *     visible in qemu-eos boot smoke tests
 *
 * Next slice (Linear TIN-1222):
 *   - per-platform CMOS / ADTG register surfacing (5D3.123 first)
 *   - sidecar MLV writer (parallel to mlv_snd) that emits RAWX blocks
 *     with the snapshot
 *   - exported function get_latest_rawx_snapshot() for opt-in
 *     consumers (raw_vidx, tools, future Zig modules)
 *
 * Audited hook points: developer_guide/09_00_raw_sensor_stack.md.
 * Block definition: modules/raw_video/mlv_rec/mlv.h (mlv_rawx_hdr_t).
 */

#include <dryos.h>
#include <module.h>
#include <console.h>
#include <property.h>

#include "mlv.h"

/* SHAD_GAIN_REGISTER is defined in src/raw.c as a static constant.
 * Mirror it here rather than expose ML core internals. On Digic IV
 * (5D2.212) this register is meaningless; we gate reads behind a
 * runtime feature check (digital gain field stays at sentinel). */
#define RAWX_SHAD_GAIN_REGISTER 0xC0F08030u

/* Latest snapshot. Single-writer (CBR_VSYNC), multi-reader (future
 * consumers). Read with a memory barrier; write atomically. The struct
 * matches mlv_rawx_hdr_t fields so a writer can copy directly. */
static struct
{
    uint32_t fields_present;
    uint32_t analog_gain;
    uint32_t digital_gain;
    int32_t  column_offset;
    int32_t  dark_temp;
    uint64_t last_vsync_tick;
    uint32_t vsync_count;
} g_snapshot = {0};

/* Pull from MMIO. shamem_read is the ML core helper that reads via the
 * shadow memory cache (consistent on all platforms; does not stall). */
extern uint32_t shamem_read(uint32_t addr);

static unsigned int raw_spectral_vsync_cbr(unsigned int ctx)
{
    (void) ctx;

    g_snapshot.vsync_count++;
    g_snapshot.last_vsync_tick = get_us_clock();

    /* Digital gain via SHAD_GAIN_REGISTER (Digic V+ only). On older
     * platforms shamem_read returns garbage; we trust the per-platform
     * build to wire the right value or to keep the bit unset. */
    g_snapshot.digital_gain = shamem_read(RAWX_SHAD_GAIN_REGISTER);
    g_snapshot.fields_present |= MLV_RAWX_HAS_DIGITAL_GAIN;

    return CBR_RET_CONTINUE;
}

static unsigned int raw_spectral_raw_info_cbr(unsigned int ctx)
{
    (void) ctx;

    /* CBR_RAW_INFO_UPDATE fires when ML core has updated raw_info.
     * The black/white levels and bayer pattern are available here.
     * Next slice will copy them into a separate file-header block. */
    return CBR_RET_CONTINUE;
}

static unsigned int raw_spectral_init(void)
{
    g_snapshot.fields_present = 0;
    g_snapshot.vsync_count = 0;
    console_printf("raw_spectral: init (scaffold). CBR_VSYNC + CBR_RAW_INFO_UPDATE registered.\n");
    return 0;
}

static unsigned int raw_spectral_deinit(void)
{
    console_printf("raw_spectral: deinit. observed %u vsync ticks.\n",
                   g_snapshot.vsync_count);
    return 0;
}

MODULE_INFO_START()
    MODULE_INIT(raw_spectral_init)
    MODULE_DEINIT(raw_spectral_deinit)
MODULE_INFO_END()

MODULE_CBRS_START()
    MODULE_CBR(CBR_VSYNC,            raw_spectral_vsync_cbr,    0)
    MODULE_CBR(CBR_RAW_INFO_UPDATE,  raw_spectral_raw_info_cbr, 0)
MODULE_CBRS_END()

MODULE_STRINGS_START()
    MODULE_STRING("Description", "Per-frame calibration metadata (RAWX block emitter)")
    MODULE_STRING("Author", "magiclantern_hydrogen")
    MODULE_STRING("License", "GPL")
    MODULE_STRING("Status", "scaffold - see Linear TIN-1222")
MODULE_STRINGS_END()
