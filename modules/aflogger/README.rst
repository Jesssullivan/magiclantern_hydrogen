aflogger
========

:Author: magiclantern_hydrogen
:License: GPL
:Summary: AF / lens / TTL telemetry (AFLG MLV block emitter)

Scaffold of the AF / lens / TTL telemetry logging module. Subscribes to
the Canon property system for AF, focus, aperture, and IS events;
emits AFLG MLV blocks into the active mlv_rec stream. Sprint C2 work
is tracked under Linear TIN-1228. Hook points are in
developer_guide/10_00_af_lens_telemetry.md. Host-side consumer is
tools/af-log/ (TIN-1230).
