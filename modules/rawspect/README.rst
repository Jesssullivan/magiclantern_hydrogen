rawspect
========

:Author: magiclantern_hydrogen
:License: GPL
:Summary: Per-frame calibration metadata (RAWX MLV block emitter)

Scaffold of the per-frame calibration metadata module for spectral and
astrophotography workflows on heavily-modified Canon DSLRs.

Implementation status is tracked under Linear TIN-1222 (Sprint B2). The
audited hook points live in src/raw.c and modules/raw_video/raw_vidx/;
the RAWX block definition lives in modules/raw_video/mlv_rec/mlv.h. The
host-side consumer is tools/raw-stack/ (Sprint B3 / TIN-1223). The
sibling module is modules/af_logger/ (Sprint C2 / TIN-1228).

This README is intentionally plain ASCII so the upstream
readme2modulestrings.py + html2text pipeline does not trip on
characters outside the embedded font table.
