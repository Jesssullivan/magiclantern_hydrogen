# magiclantern_hydrogen — Agent Instructions

This file is the working contract for coding agents and LLMs operating in
this repo. It overrides anything in `CLAUDE.md`, in nested directory
guidance, or in your global instructions when there is a conflict.

## Repo Role

`magiclantern_hydrogen` is Jess's **non-upstreamable, research-focused fork**
of Magic Lantern firmware. Origin: `github.com/Jesssullivan/magiclantern_hydrogen`.

The fork's purpose is scientific imaging on heavily-modified Canon DSLRs
(AA filter and full filter stack removed; dedicated research / instrument use):

- LOA / satellite stacking
- spectral capture (hydrogen-alpha, NIR, narrowband)
- future robotic actuation of telescope / microscope optics

It does **not** track upstream Magic Lantern. Patches do not flow back. The
community CONTRIBUTING.md in this tree describes the upstream community
posture; treat it as historical context, not as the contributor model for
this fork.

## Hierarchy of Truth

When sources disagree, the higher item wins:

1. **This file** (`AGENTS.md`)
2. `docs/spec/*.md` — dated design specs
3. `Justfile` — operator entrypoint for all build / test / release tasks
4. `developer_guide/*.md` — numbered chapter documentation
5. `README.md` — public-facing summary, subordinate to the above
6. `flake.nix`, `MODULE.bazel`, `.bazelrc` — build configuration
7. `Makefile.globals` and platform-specific `Makefile`s — firmware build
8. `doc/CODING_STYLE` — code formatting baseline (extended by `treefmt.toml`)

The plan file driving the current initiative lives at
`/Users/jess/.claude/plans/hey-there-we-are-dapper-clover.md`. Linear
initiative: `magiclantern_hydrogen — house style + raw/AF research foundation`
(team `Tinyland`).

## In-Scope Platforms (CI matrix)

Only these four are exercised by CI and by the Justfile's `build-all` /
`qemu-matrix` recipes:

- `5D2.212`
- `5D3.113`
- `5D3.123`
- `5D4.133`

Other platforms remain in `/platform` for archaeology and ad-hoc local
builds. **Do not** narrow them out of the source tree without an explicit
request — only narrow them out of the CI matrix.

`1D IV` and `1Ds III` are **future research targets, not present in the
tree**. Do not propose porting them as part of routine work; that is a
separate, dedicated initiative.

## Hard Rules

These exist because the cost of getting them wrong is high. Do not relax
them without an explicit instruction from Jess.

- **Do not run raw `bazel` or `bazelisk` locally as the default product
  path.** Enter `direnv` or `nix develop` first and prefer the shared
  cache-backed contract (`just cache-contract-strict`, then
  `just bazel-build-cached` or `scripts/bazel-cache-backed.sh build …`
  with `GF_BAZEL_SUBSTRATE_MODE=shared-cache-backed`). This mirrors the
  `GloriousFlywheel` contract.
- **Do not migrate existing firmware C en masse to Zig.** Only the
  selectively-ported hot paths in the plan's workstream B5 (mlv writer,
  dng writer, dual-iso blend) are in scope for Zig conversion. New
  modules (e.g. `raw_spectral`, `af_logger`) are Zig + C-FFI by default.
- **Do not commit secrets**, `.env`, decrypted material, credentials, or
  per-machine `user.bazelrc`.
- **Do not amend or force-push** on `dev` without explicit instruction.
  Always create a new commit.
- **Do not introduce AI attribution** in commits, PRs, code comments, or
  generated docs. No `Co-Authored-By: Claude …` lines.
- **Do not commit large binaries** (>500 KB) without first considering
  Git LFS migration. See plan workstream A5 for the inventory.
- **Do not run destructive git operations** (`reset --hard`, `push
  --force`, `branch -D`, `filter-repo` rewrites) without explicit
  instruction.

## Working Rules

- Read the nearest in-tree `AGENTS.md` (if any) before editing a
  subproject. Today only the root exists; subprojects may grow their own.
- Before claiming branch, CI, or deployment truth, check live state via
  `git`, `gh`, or Linear MCP — not memory.
- Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`, `refactor:`,
  `test:`, `wip:`). Scope is a workstream letter (`A`, `B`, `C`) or a
  module path. Example: `feat(B): emit RAWX block from raw_vidx`.
- Branch model: `dev` is the integration branch. Feature work goes on
  `feature/<short>` or `tin-<linear-id>`; PR back into `dev`.
- All build, test, lint, release, and ad-hoc operator commands have a
  `just` recipe. If you find yourself running a raw command twice, add
  it to the `Justfile`.
- Code style follows `doc/CODING_STYLE` (4-space, 80-col, LF,
  `lower_snake_case` for variables). `treefmt` enforces.

## Toolchain Contract

The hermetic toolchain comes from the flake:

- `arm-none-eabi-gcc` — firmware build (pinned in `flake.nix`)
- `zig 0.14.1` via `zig-overlay` — new modules and host-side tooling
- `python3`, `lua5.1` — ML's existing scripting deps (`scripts/`,
  `modules/lua`, `modules/tinypy`)
- `qemu` host build — host-side unit tests; the patched
  `reticulatedpines/qemu-eos` is a sibling repo, not vendored
- `bazelisk` — driven by `Justfile`, not raw
- `treefmt`, `git-cliff`, `pre-commit`, `just`

Heavy or non-cached local Bazel work is not a supported product path on
developer machines. Local flake / devshell / direnv workflows attach to
the same shared substrate that CI uses.

## Release Pipeline

Two release surfaces, both reusing the same build matrix:

- **Semver** — push a `v[0-9]+.[0-9]+.[0-9]+*` tag → `release.yml` fires.
  Tags containing `-` are marked prerelease.
- **Nightly** — daily 07:17 UTC cron + `gh workflow run nightly.yml`.
  Tag scheme `nightly-YYYYMMDD-<short-sha>`. Skipped when `dev` HEAD has
  not moved since the previous nightly. Last 7 retained; older pruned
  via `scripts/prune-nightlies.sh`.

Every release ships:

- 4 per-camera firmware tarballs (`magiclantern-hydrogen-<TAG>-<P>.tar.gz`)
  with `autoexec.bin`, `ML-SETUP.FIR`, `modules/*.mo`, `MODULES.txt`,
  `INSTALL.md`, per-platform `README.md`.
- 4 per-OS-arch host-tool tarballs (`raw-stack` / `af-log` ×
  `x86_64-linux` / `aarch64-macos`) with executable + `README.md` +
  `USAGE.md` + `LICENSE`.
- 8 SHA256 sidecars.

Both surfaces flow through three reusable workflows:

| Workflow | Purpose |
|---|---|
| `_build-firmware.yml` | Matrix over 4 platforms; uploads raw firmware artifact bundle per platform. |
| `_build-tools.yml` | Matrix over (raw-stack, af-log) × (linux x86_64 musl static, macos aarch64 native on macos-14). |
| `_publish-release.yml` | Downloads all artifacts, runs `scripts/compose-firmware-tarballs.sh` + `scripts/compose-tool-tarballs.sh`, renders body via `scripts/render-release-body.sh`, publishes via softprops. |

Release-body template (`scripts/render-release-body.sh`) is **canonical**.
Edit it, never the live release body. Per-tarball install one-liners are
in the template; per-camera install detail is in `docs/INSTALL.md`;
host-tool reference is in `docs/USAGE.md`. Both ship inside the
tarballs themselves.

Justfile entry points:

- `just release-notes-preview <TAG>` — render the body locally.
- `just nightly-trigger` / `just nightly-status` — kick / inspect runs.
- `just release <TAG>` → `just push` → `gh api PATCH /git/refs/tags/<TAG>` —
  the dev-branch push ruleset blocks direct tag push; the API path is the
  supported workaround.

For the deferred operator step that engages strict cache-substrate mode,
see Linear `TIN-1268`.

## Where to Look

| Topic | Path |
|---|---|
| Build flow + platform map | `Makefile.globals`, `platform/Makefile.platform.map`, `platform/<PLATFORM>/Makefile` |
| Core firmware | `src/` (top-level C: `raw.c`, `lens.c`, `focus.c`, `edmac.c`, `property.c`, `menu.c`, `shoot.c`, …) |
| Raw video stack | `modules/raw_video/{raw_vidx, mlv_rec, mlv_play, mlv_lite, mlv_snd}` |
| MLV library | `modules/raw_video/mlv_rec/{mlv.c, mlv.h, dng/dng.c}` |
| QEMU integration | `developer_guide/07_00_qemu_eos.md`, `minimal/qemu-*`, `src/qemu-util.h` |
| Dev guide chapters | `developer_guide/NN_NN_*.md` |
| Coding style baseline | `doc/CODING_STYLE` |

## House-Style Constellation (cross-repo references)

These siblings already run the canonical pattern; consult them when
designing new infrastructure:

- `../GloriousFlywheel` — pooled cache + runner substrate; canonical
  `MODULE.bazel`, `flake.nix`, `Justfile`, `.envrc`, `cliff.toml`,
  `renovate.json5`, `scripts/`
- `../oauth-mux`, `../zig-crypto`, `../zig-keychain`, `../zig-notify`,
  `../zig-ctap2` — Zig project pattern (`build.zig`, `nix develop
  --command zig`, C-FFI export tables in `AGENTS.md`)
- `../blahaj`, `../tinyland.dev`, `../Massageithaca`,
  `../jesssullivan-infra` — house-style AGENTS.md / CLAUDE.md / direnv /
  Justfile patterns

Do not invent new conventions when one of these already documents the
answer.
