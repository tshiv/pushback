# Changelog

All notable changes to `pushback` are documented here. Format based on
[Keep a Changelog](https://keepachangelog.com/); versioning is [SemVer](https://semver.org/).

## [Unreleased]

### Fixed
- **The archive step no longer leaks DerivedData outside the repo.** `xcodebuild archive` was the one invocation without a `-derivedDataPath`, so it fell back to `~/Library/Developer/Xcode/DerivedData/<Project>-<hash>`, where the hash is derived from the `.xcodeproj` *absolute path*. Shipping from a git worktree therefore minted a separate 2 to 3 GB cache for every worktree path, and Xcode never reclaims those when the worktree is deleted, so they accumulate silently: the leak was found at 15 orphaned directories totaling ~30 GB against 7 live worktrees. The archive now builds into `<app dir>/build/archive`, which is worktree-local and removed right after the upload.

  *Tradeoff, so this isn't mistaken for a regression later:* `build/` is wiped at the end of every successful ship, so the release archive is now always a cold build. Previously the default-location cache persisted, so a second ship from the same path reused it. This is a deliberate trade. Under a worktree-per-feature workflow most ships start from a fresh worktree where there was no cache to reuse anyway, and a hermetic release archive is worth having on its own merits. If the wall-clock cost does start to bite, the escape hatch is to stop deleting `build/archive` after the upload and exclude it from the final `build/` sweep: that leaves one warm cache per live worktree, still dying with the worktree, bounded by worktree count instead of unbounded.
- **`PUSHBACK_SIM_DEVICE` now accepts a UDID**, not just a name. A bare name is a prefix match (`iPhone 17` also resolves `iPhone 17 Pro`/`Pro Max`/`17e`, and duplicate names exist across OS runtimes), so with several matches — or two booted sims — `simctl install booted` and a device-less `maestro test` picked a device nondeterministically and flaked the QA gate. When the value is UDID-shaped it is now threaded into xcodebuild (`-destination id=`), `simctl install <udid>`, and `maestro --device <udid>`. Plain names keep the previous behavior.

## [0.1.0] — 2026-06-19

Initial release. Extracted from the `ios/ship.sh` tooling in a private app repo.

### Added
- One-command iOS TestFlight ship: verify → QA gate → (merge PR) → bump → archive → upload → commit & push.
- **Two auto-detected modes**: PR mode (open PR for the branch, or a PR number) and from-main mode (ship the current branch's state).
- **Dirty-tree handling** in from-main mode: include uncommitted changes in the bump commit, stash and ship committed HEAD only, or abort.
- Pre-ship summary + confirmation in both modes (`--yes` to skip).
- `--dry-run` that stubs the merge/archive/upload/push and reverts the bump.
- Terminal UI: banner, numbered step counters with per-step timing, `xcbeautify` streaming (spinner fallback), `NO_COLOR`/non-TTY safe.
- Config via a sourced `.pushbackrc` shell file (no YAML dependency).
- Burned-build-number safety: a bump is never reverted once the upload has succeeded.

[0.1.0]: https://github.com/tshiv/pushback/releases/tag/v0.1.0
