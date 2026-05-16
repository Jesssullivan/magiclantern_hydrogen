# 8. House Style and Build Substrate

This chapter documents the modernized developer experience for
`magiclantern_hydrogen` introduced by Linear initiative `magiclantern_hydrogen
— house style + raw/AF research foundation` (sprints A1–A7). It supersedes
the historical `scripts/check-before-hg-commit.sh` flow referenced in
`doc/CODING_STYLE`.

## 8.1 At a glance

The contract is:

```
direnv allow            # one-time per fresh clone
just                    # list every operator entrypoint
```

That's the public surface. `direnv` reads `.envrc`, which loads the Nix
devShell from `flake.nix`. The devShell provides every toolchain
(`arm-none-eabi-gcc`, `zig`, `python3`, `lua5.1`, `qemu`, `bazelisk`,
`treefmt`, `git-cliff`, `pre-commit`, `just`). All other operations go
through `just <recipe>`.

## 8.2 Source of truth hierarchy

When sources disagree, the higher item wins:

1. `AGENTS.md` (root)
2. `docs/spec/*.md` (dated design specs)
3. `Justfile`
4. `developer_guide/*.md` (this chapter and siblings)
5. `README.md`
6. `flake.nix`, `MODULE.bazel`, `.bazelrc`
7. `Makefile.globals` and platform-specific `Makefile`s
8. `doc/CODING_STYLE` (formatting baseline)

## 8.3 The file set

| File | Purpose |
|---|---|
| `AGENTS.md` | Primary agent contract; hard rules; hierarchy of truth |
| `CLAUDE.md` | Claude-specific overlay deferring to `AGENTS.md` |
| `.envrc` | direnv config; loads flake; attaches attic cache when keys present |
| `flake.nix` | Hermetic devShell, treefmt config, formatter check |
| `Justfile` | SSOT for build / test / lint / qemu / cache / release |
| `MODULE.bazel` | bzlmod module declaration (host-side tooling and CI orchestration) |
| `BUILD.bazel` | Root Bazel package |
| `.bazelversion`, `.bazelrc` | Bazel pinning + bzlmod + cache config |
| `.clang-format` | C/C++ formatter rules mirroring `doc/CODING_STYLE` |
| `.gitattributes` | LF normalization + binary markers + LFS candidates |
| `.pre-commit-config.yaml` | Pre-commit hooks wrapping `just fmt-check` + `just lint` |
| `cliff.toml` | git-cliff conventional-commits CHANGELOG generation |
| `renovate.json5` | Renovate dep automation |
| `scripts/bazel-cache-backed.sh` | Bazel wrapper enforcing cache contract |
| `scripts/cache-attachment-contract.sh` | Cache attachment classifier |
| `.github/workflows/` | CI: `ci.yml`, `qemu-matrix.yml`, `release.yml`, `renovate-pin.yml` |

## 8.4 Coding style

Code formatting follows `doc/CODING_STYLE`:

- 4-space indents, no tabs (except syntactically-required Makefile indents)
- 80-character line width
- LF line endings
- `lower_snake_case` for variables
- Allman brace style

`treefmt` enforces this via `clang-format` for C/H sources. Other
languages get their canonical formatter:

| Language | Formatter |
|---|---|
| C / C++ | clang-format |
| Zig | zig fmt |
| Markdown / YAML / JSON | prettier |
| Nix | alejandra |
| TOML | taplo |
| Shell | shfmt |

`treefmt.toml` settings live inside `flake.nix` under `treefmtEval`.

Vendored or upstream-tracked sources are excluded from `treefmt`:

- `src/libs/**`
- `tcc/**`
- `minimal/qemu-*/**`

## 8.5 The Justfile contract

`just` lists every recipe. The canonical operator entrypoints:

| Recipe | Purpose |
|---|---|
| `just setup` | First-time bootstrap (idempotent) |
| `just info` | Toolchain versions, cache status, in-scope platforms |
| `just fmt` | Format every supported file in the tree |
| `just fmt-check` | Check formatting without writing |
| `just lint` | clang-tidy on touched C, `zig build test` on Zig modules |
| `just build PLATFORM=5D3.123` | Build a single platform (wraps Make) |
| `just build-all` | Build every in-scope platform |
| `just build-modules` | Build modules independent of platform |
| `just clean` | Clean build artifacts |
| `just qemu-test PLATFORM=5D3` | Boot the platform in qemu-eos |
| `just qemu-matrix` | All in-scope platforms × qemu |
| `just test` | Host-side Bazel + Zig tests |
| `just ci-local` | Full local CI mirror |
| `just cache-contract` | Describe cache attachment state |
| `just cache-contract-strict` | Strict attachment check (exits nonzero on miss) |
| `just bazel-build-cached TARGET` | Bazel build through the shared cache |
| `just bazel-test-cached TARGET` | Bazel test through the shared cache |
| `just mlv-decode FILE` | Host MLV → DNG via calibration-aware pipeline (B3) |
| `just af-log-replay FILE` | Replay AF log capture (C4) |
| `just changelog` | Regenerate `CHANGELOG.md` via git-cliff |
| `just release VERSION` | Tag, regen CHANGELOG, push |

Recipes for unimplemented workstreams (qemu wiring, host MLV, AF log)
stub out with a pointer to the relevant Linear issue and exit nonzero,
so the gap is visible.

## 8.6 In-scope platforms

CI exercises four platforms (the rest remain in tree for archaeology and
ad-hoc local builds):

- `5D2.212`
- `5D3.113`
- `5D3.123`
- `5D4.133`

When narrowing the CI matrix in `.github/workflows/ci.yml` or in
`build-all`, this is the source list. **Do not** remove non-in-scope
platforms from the source tree; only narrow them out of automated builds.

## 8.7 Flywheel cache substrate

The shared substrate is `GloriousFlywheel` (sibling repo
`../GloriousFlywheel`). Conceptually:

- Nix builds attach to the Attic substituter at
  `${ATTIC_SERVER}/${ATTIC_CACHE}` (default `https://nix-cache.tinyland.dev/main`).
- Bazel builds attach to `BAZEL_REMOTE_CACHE` (operator-provided).
- Local developer machines only enter `shared-cache-backed` mode when
  `BAZEL_REMOTE_CACHE` is explicitly set. Otherwise the substrate mode
  is `compatibility-local-only` (heavy work is not normalized as a
  product path).

Hard rule (mirrored from `GloriousFlywheel/AGENTS.md` into our
`AGENTS.md`): **do not run raw `bazel` or `bazelisk` locally as the
default product path.** Use `just bazel-build-cached <target>` or
`scripts/bazel-cache-backed.sh build <target>`. Those validate the
attachment contract first via `scripts/cache-attachment-contract.sh`.

Setup:

1. Operator provides `ATTIC_PUBLIC_KEY` (and any `BAZEL_REMOTE_CACHE`)
   via `.env` or environment.
2. `direnv allow` re-loads with the attic substituter appended to
   `NIX_CONFIG`.
3. `just cache-contract-strict-nix` verifies attachment from the dev
   shell. CI runs the same check.

## 8.8 CI on GitHub Actions

Workflows under `.github/workflows/`:

- `ci.yml` — PR gate: fmt-check, lint, build for the in-scope matrix,
  cache-contract description.
- `qemu-matrix.yml` — nightly (cron) + workflow_dispatch + on PR label
  `qemu-please`. Currently fails until TIN-1217 wires qemu-eos.
- `release.yml` — on tag push (`v*.*.*`) or workflow_dispatch with a tag
  input. Builds firmware, generates release notes via git-cliff,
  attaches firmware artifacts.
- `renovate-pin.yml` — weekly companion to Renovate; refreshes
  `flake.lock` via `nix flake update` and opens a PR.

All workflows attach to the attic cache when the
`ATTIC_PUBLIC_KEY` repo secret and `ATTIC_SERVER` / `ATTIC_CACHE`
repository variables are set.

## 8.9 Commit and release flow

Conventional Commits format:

```
<type>(<scope>): <subject>

<body>

<footer>
```

Types: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `build`,
`ci`, `perf`, `style`, `wip`. Scope is a workstream letter (`A`, `B`,
`C`) or a module path. Examples:

- `feat(B): emit RAWX block from raw_vidx`
- `fix(5D3.123): correct ADTG bit ordering`
- `docs(A6): update developer_guide/08 with treefmt notes`

No AI attribution lines (`Co-Authored-By: Claude ...` etc.).
`cliff.toml` strips them defensively in CHANGELOG generation.

Releases:

```
just release v0.1.0
```

This runs `git-cliff --tag v0.1.0`, commits the regenerated
`CHANGELOG.md`, creates an annotated tag, and pushes with
`--follow-tags`. The `release.yml` workflow takes over on tag push.

## 8.10 Branch model

- `dev` is the integration branch (matches `origin/HEAD`).
- Feature work goes on `feature/<short>` or `tin-<linear-id>`.
- PRs merge into `dev`.
- Branch protection on `dev`: PR required + CI green required + 0
  reviewers (solo project).
- No force-push to `dev`.
- No amending `dev` commits — make a new commit instead.

## 8.11 Where to next

- `developer_guide/09_00_raw_sensor_stack.md` — raw / sensor stack
  current-state map (Sprint B1).
- `developer_guide/10_00_af_lens_telemetry.md` — AF / lens / TTL surface
  map (Sprint C1).
- Linear: initiative `magiclantern_hydrogen — house style + raw/AF
  research foundation`, team `Tinyland`.
