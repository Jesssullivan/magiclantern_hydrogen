# af-log

Host CLI for `AFLG` MLV blocks emitted by `modules/af_logger/` on
magiclantern_hydrogen.

**Status**: scaffold + AFLG decoder + `replay` + `summary` subcommands.
`detect` pattern classifier is the next slice.
**Linear**: TIN-1230 (Sprint C4).

## Build

From the repo root, inside the dev shell:

```
direnv allow
cd tools/af-log
zig build
./zig-out/bin/af-log replay path/to/capture.mlv
```

Or `zig build test`.

### macOS local-build caveat

See the matching note in `tools/raw-stack/README.md`. The nixpkgs-Darwin
+ Zig + MacOSX 26.5 SDK combination produces libc linker errors at
build time. Use Linux CI or a non-nix Zig install while this is open.

## Subcommands

| Subcommand | Status | Purpose |
|---|---|---|
| `replay FILE.mlv` | **implemented** | Annotated event-by-event timeline |
| `summary FILE.mlv` | **implemented** | Counts per event type |
| `detect FILE.mlv` | stub | Focus-bracket / tracking / hunting pattern classifier |

## Block format

`AFLG` wire layout mirrors `mlv_aflg_hdr_t` in
`modules/raw_video/mlv_rec/mlv.h`. The `fields_present` bitmap
distinguishes platform-supported fields from absent ones (e.g. 5D3 has
no `PROP_LENS_DYNAMIC_DATA`).

## Pairs with

- `modules/af_logger/` — firmware-side AFLG emitter (TIN-1228)
- `docs/spec/robotic-optics-actuation-2026-05-16.md` — future-state
  design that consumes AFLG timelines for stepper/servo control.
