# af-log

Host-side Zig CLI for AFLG telemetry blocks emitted by the
`aflogger` firmware module in `magiclantern_hydrogen`. Replays event
timelines, summarises by event type, and detects common AF / lens
intent patterns (focus-bracket, tracking-dwell, hunting).

## Quick start

```
af-log replay  lens-test.mlv | less
af-log summary lens-test.mlv
af-log detect  lens-test.mlv
```

See [`USAGE.md`](USAGE.md) for the full subcommand reference.

## Build from source

```
cd tools/af-log
zig build                                # native target, ReleaseSafe
zig build test                           # unit tests
zig build -Dtarget=x86_64-linux-musl     # static Linux binary
zig build -Dtarget=aarch64-macos         # macOS Apple Silicon
```

Requires Zig 0.14.

## Source layout

| File | Purpose |
|---|---|
| `src/main.zig` | CLI entry + subcommand dispatch. |
| `src/mlv.zig` | Shared MLV decoder (block headers, AFLG payload). |
| `src/detect.zig` | Pattern classifiers (focus_bracket / tracking_dwell / hunting). |

## Bundled in releases

Every release tarball contains: `af-log` (executable), `README.md`
(this file), `USAGE.md` (full reference), `LICENSE`.

## License

GPL-2.0, inherited from the parent repo. See `LICENSE`.
