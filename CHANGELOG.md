# Changelog

All notable changes to `pushback` are documented here. Format based on
[Keep a Changelog](https://keepachangelog.com/); versioning is [SemVer](https://semver.org/).

## [Unreleased]

## [0.1.1] - 2026-09-05

### Fixed
- **A failed or rehearsed ship no longer discards your own uncommitted `project.yml` edits.** In from-main mode with the `include` choice, the revert after a pre-upload failure (and at the end of every `--dry-run`) ran `git checkout --` on the commit paths, which reset `project.yml` and the `.xcodeproj` to HEAD and silently threw away whatever edits you had there. pushback now snapshots your state of those paths right after the dirty-tree decision and restores to that snapshot instead of to HEAD. Staged and unstaged edits are both preserved as content (the staged split is not, since include mode stages everything anyway). If the patch can't be re-applied it is kept at `<repo>/pushback-preship.patch` with the exact command to apply it. Stash mode and clean trees behave exactly as before.
- **The pre-ship stash is restored by commit SHA, not by stack position.** `git stash pop` takes whatever is on top of the stash stack, and that stack is shared across every worktree of the repo. Another session pushing a stash during the multi-minute archive meant pushback popped the wrong entry and left its own behind. The stash is now pushed with a unique message, its SHA recorded, and restored with `stash apply <sha>` followed by a drop of that specific entry. The recovery hint on a conflict names the SHA.

### Changed
- Removed em dashes from all user-facing output and docs. No behavior change.
- **The archive step no longer leaks DerivedData outside the repo.** `xcodebuild archive` was the one invocation without a `-derivedDataPath`, so it fell back to `~/Library/Developer/Xcode/DerivedData/<Project>-<hash>`, where the hash is derived from the `.xcodeproj` *absolute path*. Shipping from a git worktree therefore minted a separate 2 to 3 GB cache for every worktree path, and Xcode never reclaims those when the worktree is deleted, so they accumulate silently: the leak was found at 15 orphaned directories totaling ~30 GB against 7 live worktrees. The archive now builds into `<app dir>/build/archive`, which is worktree-local and removed right after the upload.

  *Tradeoff, so this isn't mistaken for a regression later:* `build/` is wiped at the end of every successful ship, so the release archive is now always a cold build. Previously the default-location cache persisted, so a second ship from the same path reused it. This is a deliberate trade. Under a worktree-per-feature workflow most ships start from a fresh worktree where there was no cache to reuse anyway, and a hermetic release archive is worth having on its own merits. If the wall-clock cost does start to bite, the escape hatch is to stop deleting `build/archive` after the upload and exclude it from the final `build/` sweep: that leaves one warm cache per live worktree, still dying with the worktree, bounded by worktree count instead of unbounded.
- **`PUSHBACK_SIM_DEVICE` now accepts a UDID**, not just a name. A bare name is a prefix match (`iPhone 17` also resolves `iPhone 17 Pro`/`Pro Max`/`17e`, and duplicate names exist across OS runtimes), so with several matches, or two booted sims, `simctl install booted` and a device-less `maestro test` picked a device nondeterministically and flaked the QA gate. When the value is UDID-shaped it is now threaded into xcodebuild (`-destination id=`), `simctl install <udid>`, and `maestro --device <udid>`. Plain names keep the previous behavior.

## [0.1.0] - 2026-06-19

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

[0.1.1]: https://github.com/tshiv/pushback/releases/tag/v0.1.1
[0.1.0]: https://github.com/tshiv/pushback/releases/tag/v0.1.0
