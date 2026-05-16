# Claude Code — magiclantern_hydrogen

`AGENTS.md` is the source of truth. Read it first. This file is a slim
overlay for Claude Code with a few operational reminders.

## Critical reminders

1. **Read `AGENTS.md` first.** Everything important is there, including the
   hierarchy of truth, in-scope platforms, hard rules, and toolchain
   contract.
2. **Read the nearest in-tree `AGENTS.md`** before editing a subproject if
   one exists.
3. **Batch independent tool calls.** Most exploration here spans `src/`,
   `modules/`, `platform/`, and sibling repos under `~/git`; parallelize.
4. **Use the `Justfile`** for build / test / lint / qemu / cache / release.
   Don't invoke `make`, `bazel`, `zig`, `nix build`, or `arm-none-eabi-gcc`
   directly outside of debugging.
5. **Live state, not memory** for branch / CI / Linear truth. Use `gh`,
   `git`, and Linear MCP. Memory snapshots decay.
6. **No AI attribution.** Do not add `Co-Authored-By: Claude …` lines or
   similar marks to commits, PRs, code comments, or generated docs.

## Project context (short)

Research-focused fork of Magic Lantern. Three goals:

1. House style + bazel/nix/just/direnv standardization, Flywheel attic
   cache integration, GitHub Actions CI, repo hygiene.
2. Raw / sensor stack for spectral / astro capture on modified 5D2/3/4
   (AA filter + filter stack removed). Calibration-grade MLV metadata
   (`RAWX` block), host-side Zig reconstruction pipeline.
3. AF / lens / TTL telemetry logging (`AFLG` block, `af_logger` module)
   for future robotic optics actuation.

In-scope CI platforms: `5D2.212`, `5D3.113`, `5D3.123`, `5D4.133`.
1D IV / 1Ds III are future research targets, not in tree.

Plan file: `/Users/jess/.claude/plans/hey-there-we-are-dapper-clover.md`.
Linear: initiative `magiclantern_hydrogen — house style + raw/AF research
foundation`, team `Tinyland`.
