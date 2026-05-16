af_logger
=========

AF / lens / TTL telemetry logging module for future robotic optics
actuation workflows.

**Status**: scaffold only. Implementation tracked under Linear TIN-1228
(Sprint C2). See ``developer_guide/10_00_af_lens_telemetry.md`` for the
audited property IDs and event hook surfaces, and
``docs/spec/robotic-optics-actuation-2026-05-16.md`` for the
forward-looking actuation design.

What it does
------------

Subscribes to the Canon property system for AF, lens, and TTL events
and emits ``AFLG`` MLV blocks to the active recording stream:

============================================  =================================
Event                                         Source
============================================  =================================
half-press transition                         PROP_HALF_SHUTTER (focus.c:872)
AF cycle complete                             PROP_LV_FOCUS_DONE (focus.c:832)
continuous focus magnitude (per-vsync)        PROP_LV_FOCUS_DATA (focus.c:1001)
AF point selection                            PROP_AFPOINT
AF area / mode                                PROP_LV_AFFRAME (zebra.c:638)
aperture commanded                            PROP_APERTURE (lens.c:1631)
IS state change                               PROP_LV_LENS_STABILIZE (lens.c:1461)
DIGIC8+ rich lens telemetry                   PROP_LENS_DYNAMIC_DATA (lens.c:1952)
============================================  =================================

Block definition lives in ``modules/raw_video/mlv_rec/mlv.h``
(``mlv_aflg_hdr_t``).

Platform deltas
---------------

- **5D3** (5D3.113, 5D3.123): no ``PROP_LENS_DYNAMIC_DATA``. Lens
  dynamic fields in the AFLG block carry ``MLV_RAWX_SENTINEL_U16``.
  ``PROP_AFMA`` available.
- **5D4** (5D4.133): full ``PROP_LENS_DYNAMIC_DATA`` (focus near/far/pos,
  IS state, AF/MF physical switch).

Observability bound
-------------------

This module operates at the Canon **property layer** only. Raw EF-mount
bus traffic is **not** observable from firmware (see
``docs/spec/ef-mount-ttl-observation-2026-05-16.md``). Future
robotic-optics work requiring bus-level telemetry needs an external
mount sniffer.

Zig migration (deferred)
------------------------

Like ``raw_spectral``, the plan flags ``af_logger`` as a Zig + C FFI
pilot. Zig integration is a separate spike; initial implementation is
plain C.

Pairs with
----------

- ``modules/raw_spectral`` (TIN-1222) — same MLV stream, imaging side.
- ``tools/af-log`` (TIN-1230) — host CLI for AFLG capture analysis.
