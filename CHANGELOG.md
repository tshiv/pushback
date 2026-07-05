# Changelog

All notable changes to `pushback` are documented here. Format based on
[Keep a Changelog](https://keepachangelog.com/); versioning is [SemVer](https://semver.org/).

## [Unreleased]

### Fixed
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
