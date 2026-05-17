# raw-stack

Host-side Zig CLI for `magiclantern_hydrogen` MLV captures. Decodes MLV
blocks (RAWI, VIDF, RAWX, AFLG), unpacks 14-bit packed Bayer pixels,
computes RGGB plane statistics, and runs per-pixel stacking operations
(mean, median, sigma-clipped, dark-subtracted) with FITS or raw u16
output.

## Quick start

```
raw-stack info my-capture.mlv          # camera geometry from RAWI
raw-stack median-frame darks/*.mlv master-dark.bin
raw-stack dark-subtract master-dark.bin lights/*.mlv reduced.fits
raw-stack sigma-stack --sigma 2.5 --iters 3 spectral/*.mlv spectral.fits
```

See [`USAGE.md`](USAGE.md) for the full subcommand reference.

## Build from source

```
cd tools/raw-stack
zig build                                # native target, ReleaseSafe
zig build test                           # unit tests
zig build -Dtarget=x86_64-linux-musl     # static Linux binary
zig build -Dtarget=aarch64-macos         # macOS Apple Silicon
```

Requires Zig 0.14. The repo's `flake.nix` pins
[`nixpkgs#zig_0_14`](https://search.nixos.org/packages?query=zig_0_14).

## Source layout

| File | Purpose |
|---|---|
| `src/main.zig` | CLI entry + subcommand dispatch. |
| `src/mlv.zig` | MLV block header + RAWI/VIDF/RAWX/AFLG decoders. |
| `src/pixels.zig` | 14-bit packed-Bayer codec matching `struct raw_pixblock`. |
| `src/bayer.zig` | RGGB plane decomposition + summary stats. |
| `src/fits.zig` | Minimal FITS image writer. |
| `src/fixture.zig` | Synthetic MLV generator for tests + integration. |
| `src/stack.zig` | RAWX metadata aggregator. |

## Bundled in releases

Every release tarball contains: `raw-stack` (executable), `README.md`
(this file), `USAGE.md` (full reference), `LICENSE`.

## License

GPL-2.0, inherited from the parent repo. See `LICENSE`.
