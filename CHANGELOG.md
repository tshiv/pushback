# Changelog

All notable changes to `pushback` are documented here. Format based on
[Keep a Changelog](https://keepachangelog.com/); versioning is [SemVer](https://semver.org/).

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
