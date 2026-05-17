# magiclantern_hydrogen

[![ci](https://github.com/Jesssullivan/magiclantern_hydrogen/actions/workflows/ci.yml/badge.svg)](https://github.com/Jesssullivan/magiclantern_hydrogen/actions/workflows/ci.yml)
[![release](https://img.shields.io/github/v/release/Jesssullivan/magiclantern_hydrogen?display_name=tag&filter=v*)](https://github.com/Jesssullivan/magiclantern_hydrogen/releases/latest)
[![nightly](https://img.shields.io/github/v/release/Jesssullivan/magiclantern_hydrogen?display_name=tag&filter=nightly-*&label=nightly)](https://github.com/Jesssullivan/magiclantern_hydrogen/releases?q=prerelease%3Atrue)

A non-upstreamable, research-focused fork of [Magic Lantern](https://magiclantern.fm)
for **spectral / astrophotography / future robotic-optics** work on
heavily-modified Canon DSLRs (AA filter + filter stack removed).

This repo bundles three things into every release:

1. **Firmware** for the four in-scope cameras: `5D2.212`, `5D3.113`,
   `5D3.123`, `5D4.133`.
2. **`raw-stack`** — host-side Zig CLI for decoding MLV captures,
   per-pixel mean / median / sigma-clipped stacking, master-dark subtract,
   FITS / raw-u16 output, RGGB plane statistics.
3. **`af-log`** — host-side Zig CLI for AFLG telemetry replay, summary,
   and classifier-based pattern detection (focus_bracket / tracking_dwell /
   hunting).

## Supported platforms

| Camera | Firmware | Status | Tarball |
|---|---|---|---|
| Canon 5D Mark II | 2.1.2 | CI green | `magiclantern-hydrogen-<TAG>-5D2.212.tar.gz` |
| Canon 5D Mark III | 1.1.3 | CI green | `magiclantern-hydrogen-<TAG>-5D3.113.tar.gz` |
| Canon 5D Mark III | 1.2.3 | CI green | `magiclantern-hydrogen-<TAG>-5D3.123.tar.gz` |
| Canon 5D Mark IV | 1.3.3 | CI green | `magiclantern-hydrogen-<TAG>-5D4.133.tar.gz` |

1D Mark IV / 1Ds Mark III are documented research targets but **not in
the CI matrix**.

## Install firmware

Grab the [latest release](https://github.com/Jesssullivan/magiclantern_hydrogen/releases/latest),
pick the tarball for your camera, extract it to your SD card root, boot.

```bash
PLATFORM=5D3.123
TAG=$(gh release view --repo Jesssullivan/magiclantern_hydrogen --json tagName -q .tagName)
curl -L "https://github.com/Jesssullivan/magiclantern_hydrogen/releases/download/${TAG}/magiclantern-hydrogen-${TAG}-${PLATFORM}.tar.gz" | tar xz
cp -r "magiclantern-hydrogen-${TAG}-${PLATFORM}/"* /Volumes/EOS_DIGITAL/
diskutil unmount /Volumes/EOS_DIGITAL
```

Full procedure (SD-card prep, firmware update, recovery, uninstall):
[`docs/INSTALL.md`](docs/INSTALL.md).

## Host tools

```bash
TAG=$(gh release view --repo Jesssullivan/magiclantern_hydrogen --json tagName -q .tagName)
curl -L "https://github.com/Jesssullivan/magiclantern_hydrogen/releases/download/${TAG}/raw-stack-${TAG}-x86_64-linux.tar.gz" | tar xz
./raw-stack-${TAG}-x86_64-linux/raw-stack info my-capture.mlv
```

Reference (every subcommand, every flag, real examples):
[`docs/USAGE.md`](docs/USAGE.md) — also bundled in each tool tarball.

Today's tool matrix:

| Tool | Linux x86_64 | macOS aarch64 |
|---|---|---|
| `raw-stack` | static musl | native |
| `af-log` | static musl | native |

Linux aarch64 / Windows are out of scope for this cycle.

## Build from source

Hermetic dev shell via Nix flake:

```bash
direnv allow            # auto-loads flake on cd
just info               # toolchain versions
just build 5D3.123      # one firmware platform
just build-all          # all four
just tools-build-all    # raw-stack + af-log for both shipped targets
just tools-test         # zig build test for every tool
```

CI uses the same recipes (see [`.github/workflows/`](.github/workflows/)).

## Releases

- **Semantic versions** (`v0.X.Y`) — driven by tag push; triggers
  [`release.yml`](.github/workflows/release.yml). Each release bundles
  all four firmware platforms + all four (tool × OS-arch) tarballs +
  SHA256 sidecars.
- **Nightlies** (`nightly-YYYYMMDD-<sha>`) — daily at 07:17 UTC via
  [`nightly.yml`](.github/workflows/nightly.yml). Skipped if `dev` HEAD
  hasn't moved since the previous nightly. Last 7 retained.

Preview a release body locally before tagging:

```bash
just release-notes-preview v0.4.0
```

## Hack on it

- [`AGENTS.md`](AGENTS.md) — operator runbook + house-style rules (the
  source of truth for repository contracts).
- [`CLAUDE.md`](CLAUDE.md) — slim Claude Code overlay deferring to
  AGENTS.md.
- [`developer_guide/`](developer_guide/) — numbered chapters covering the
  raw / sensor stack (chapter 09), AF / lens telemetry (10), QEMU (07),
  etc.
- [`docs/spec/`](docs/spec/) — dated design specs (robotic optics
  actuation, EF-mount TTL observation).
- Linear initiative: `magiclantern_hydrogen — house style + raw/AF
  research foundation` on the Tinyland team.

## Relationship to upstream

This fork descends from
[`reticulatedpines/magiclantern_simplified`](https://github.com/reticulatedpines/magiclantern_simplified).
The upstream README is preserved at [`README.upstream.md`](README.upstream.md).

This fork is intentionally **non-upstreamable** — it removes platforms
that aren't part of the spectral / astro research scope and adds
calibration metadata blocks (`RAWX`) plus AF telemetry blocks (`AFLG`)
that have no analogue in mainline ML.

## License

GPL-2.0 (inherited from upstream Magic Lantern). See [`LICENSE`](LICENSE).
