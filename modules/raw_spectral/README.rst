raw_spectral
============

:Author: magiclantern_hydrogen
:License: GPL
:Summary: Per-frame calibration metadata (RAWX MLV block emitter)

Per-frame calibration metadata module for spectral and astrophotography
workflows on heavily-modified Canon DSLRs.

**Status**: scaffold only. Implementation tracked under Linear TIN-1222
(Sprint B2). See `developer_guide/09_00_raw_sensor_stack.md` for the
audited hook points in `src/raw.c` and `modules/raw_video/raw_vidx/`.

What it does
------------

Subscribes to `raw_vidx` per-frame events and emits a ``RAWX`` MLV block
alongside every video frame. The ``RAWX`` block carries calibration-grade
metadata that the host pipeline (``tools/raw-stack``, Sprint B3) needs
for ISO-pushing reconstruction:

- analog gain
- digital gain (``SHAD_GAIN_REGISTER`` on Digic V+; sentinel on Digic IV)
- column offset table reference
- dark-current sensor temperature
- DPC and FPN table snapshot references
- precise nanosecond exposure timestamp

Block definition lives in ``modules/raw_video/mlv_rec/mlv.h``
(``mlv_rawx_hdr_t``).

In-scope platforms (CI matrix)
-------------------------------

- 5D2.212 (Digic IV; ``digital_gain`` field set to sentinel)
- 5D3.113, 5D3.123 (Digic V+)
- 5D4.133 (Digic 6+)

Build
-----

Standard ML module build via ``make`` from this directory or
``make raw_spectral`` from the repo root after entering the dev shell::

    direnv allow
    just build-modules

Per-platform CMOS / ADTG register surfacing is platform-specific. The
first implementation will target 5D3.123 because the ``cmos_iso_t`` /
``adtg_iso_t`` tables there are the most exercised by existing modules
(``dual_iso``, ``crop_rec``).

Zig migration (deferred)
------------------------

The plan calls for ``raw_spectral`` to be a Zig + C FFI pilot. The
``build.zig`` and ``build.zig.zon`` skeletons here document that
intent. Actual Zig→ARM bare-metal cross-compile integration with ML's
TCC-based module loader is a separate spike (out of scope for this
sprint slice); the initial implementation is plain C.

Pairs with
----------

- ``modules/af_logger`` (Sprint C2 / TIN-1228) — same MLV stream, AF
  telemetry side.
- ``tools/raw-stack`` (Sprint B3 / TIN-1223) — host pipeline consumer.
