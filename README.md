# pushback

**From the gate to the App Store, in one command.** Ship an iOS app to
TestFlight from your laptop. No CI, no Ruby, no Fastlane setup tax.

```bash
pushback            # auto-detects: open PR → merge & ship, else ship current branch
pushback --dry-run  # rehearse the whole thing: no merge, no upload, no push
pushback doctor     # check everything a ship needs, change nothing
```

`pushback` is a single, dependency-light bash script that does the entire
release in one pass:

**verify build → QA gate → (merge PR) → bump version → archive → upload → commit & push.**

The name is the joke and the spec: in aviation, *pushback* is the tug easing
the plane off the gate, the first move of departure. And it's what you do to
ship: `git push`, then watch it go.

---

## Why not Fastlane?

Fastlane is great for teams of three sharing certificates (`match`), for
automating App Store metadata and screenshots, and for running inside CI. If
that's you, use Fastlane.

`pushback` is for the other case: **one app, one person, shipping from a
laptop, no CI.** There, Fastlane is mostly setup tax for features you don't
use, and you *still* end up writing glue for the parts it doesn't cover, like
merging the right PR or running a smoke test before `main` is touched.
`pushback` is that glue, made first-class:

- **PR-aware.** Detects the open PR for your branch, checks your local HEAD
  matches it, and verifies the build *before* the squash-merge, so a broken iOS
  build can't land in `main`.
- **Ships from `main` too.** No PR? Already merged? It ships the current
  branch's actual state, including uncommitted changes if you want.
- **Pre-merge QA gate.** Unit/snapshot tests, plus Maestro smoke flows if
  installed, before anything irreversible happens.
- **Smart rollback.** Knows the one thing you must never do, revert a build
  number *after* the upload burned it in App Store Connect, and never does it.
- **One command.** Laptop → TestFlight, no context-switch to a CI dashboard.

It deliberately does **not** try to be Fastlane. It drives `xcodebuild`, `git`,
`gh`, and `xcodegen` directly. iOS-focused today; the merge → bump → ship
skeleton would extend to other targets, but `pushback` doesn't pretend to be
multi-platform until it is.

---

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/tshiv/pushback/main/install.sh | bash
```

Or grab the one file and put it on your `PATH`:

```bash
curl -fsSL https://raw.githubusercontent.com/tshiv/pushback/main/pushback -o /usr/local/bin/pushback
chmod +x /usr/local/bin/pushback
```

**Requires:** `git`, [`gh`](https://cli.github.com), `xcodegen`, Xcode (real
`xcodebuild`, not Command Line Tools), and an App Store Connect API key.

**Optional**, auto-detected, gracefully skipped if missing:
- [`xcbeautify`](https://github.com/cpisciotta/xcbeautify): prettier build output (`brew install xcbeautify`)
- [`maestro`](https://maestro.mobile.dev): UI smoke flows in the QA gate

Set up an App Store Connect API key (App Store Connect → Users and Access →
Integrations → Keys), download the `.p8`, and place it at
`~/.private_keys/AuthKey_<KEYID>.p8`. Put the key id + issuer id in `.env.local`
(or export them):

```
APPSTORE_CONNECT_API_KEY_ID=XXXXXXXXXX
APPSTORE_CONNECT_API_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

Your `ExportOptions.plist` must set `destination=upload` so the single
`-exportArchive` step both packages *and* uploads (no `altool` follow-up).
pushback checks this before it builds anything.

---

## Setup

Copy the sample config to your project and edit it:

```bash
curl -fsSL https://raw.githubusercontent.com/tshiv/pushback/main/.pushbackrc.example -o ios/.pushbackrc
```

`.pushbackrc` is sourced shell (no YAML parser needed). In most projects you
only need `PUSHBACK_SCHEME`; everything else derives from it or has a default:

```sh
PUSHBACK_PRODUCT_NAME="my app"
PUSHBACK_APP_DIR="ios"
PUSHBACK_SCHEME="MyApp"
```

Then check it, and rehearse a ship (point `--config` at your `.pushbackrc`,
or drop a `.pushbackrc` next to the binary / in the working directory):

```bash
pushback --config ios/.pushbackrc doctor
pushback --config ios/.pushbackrc --dry-run
```

`doctor` lists every problem at once: missing tools, Xcode pointing at the
Command Line Tools, `gh` not signed in, a missing App Store Connect key, an
`ExportOptions.plist` that won't upload, a simulator that no longer exists,
origin unreachable, a stale build number, leftovers from an earlier failed
ship. It changes nothing apart from a `git fetch`.

A common pattern is a tiny wrapper script checked into your repo:

```bash
#!/bin/bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
exec pushback --config "$DIR/.pushbackrc" "$@"
```

---

## Usage

```bash
pushback [options] [PR_NUMBER]
```

| Invocation | What happens |
|---|---|
| `pushback` | Auto-detect. Open PR for the branch → PR mode. Else → from-main mode. |
| `pushback 37` | Merge + ship PR #37. |
| `pushback --from-main` | Force from-main mode (ignore any PR). Alias: `--no-merge`. |
| `pushback --dry-run` | Run everything reversible; **stub** merge, archive, upload, push; revert the bump. |
| `pushback --skip-qa` | Skip the unit-test + Maestro gate. |
| `pushback --yes` | Don't prompt. A dirty tree is included wholesale. |
| `pushback --dirty stash` | Decide a dirty tree up front: `include`, `stash`, or `abort` (add `--yes` for unattended runs). |
| `pushback doctor` | Check the toolchain, config, key, simulator and repo state. Ships nothing. |
| `pushback --config <path>` | Point at a specific `.pushbackrc` (default: `./.pushbackrc`). |

### Modes

**PR mode.** There's an open PR for the current branch (or you passed a PR
number). `pushback` verifies the build on the PR branch, runs QA,
squash-merges, fast-forwards to `origin/main`, then ships. Requires a clean
working tree (you're shipping the PR's code). Works from a git worktree too:
if `main` is checked out in another worktree, it ships from a detached
`origin/main` and pushes the bump with `HEAD:main`. A local `main` that has
diverged from `origin/main` stops the run rather than being merged or reset.

**From-main mode.** No open PR; you're on `main` (already merged) or a local
branch. `pushback` ships the current branch's current state and pushes the
version bump to that branch. If the tree is dirty it asks what to do:

```
Ship these changes?
  i  include them in the version-bump commit and ship
  s  stash them, ship committed HEAD only, restore after
  d  show full diff
  a  abort
```

`include` folds your uncommitted work into the bump commit (the build already
reads your working tree, so this is literally "ship what I see"). `stash` ships
only committed HEAD and restores your changes afterward, and never drops the
stash on a conflict.

Both modes show a one-line summary and ask for confirmation before the
irreversible archive+upload. `--yes` skips the prompts.

### The build-number invariant

Once `-exportArchive` succeeds, the bumped build number is **burned** in App
Store Connect. Reusing it fails validation. So `pushback`'s failure handler:

- reverts the bump if it failed **before** the upload was attempted,
- **leaves the bump in place** and tells you to commit it if the upload failed
  (App Store Connect may have received the build anyway) or succeeded but the
  commit/push failed,
- tells you to just push if the commit landed but the push failed.

It never reverts a build number that might be burned. A skipped number costs
nothing; a reused one fails a whole archive later.

Three guards keep it from reaching for a burned number in the first place:

- **A record of burned numbers.** The moment an upload starts, its build
  number goes into `.git/pushback.burned` (one file per clone, shared by its
  worktrees, one line per app). A later ship from that clone won't bump to it again, even if the
  kept bump was stashed, discarded, or reset away.
- **One ship per repo at a time.** A lock in the repo's shared git dir stops a
  second `pushback` (from any worktree) until the first finishes, since both
  would bump to the same build. A lock left by a killed run is taken over.
- **Stale-build check.** Before bumping, it compares your build number with
  `main`, `origin/main` and the target branch. If any of them is ahead (for
  example, local `main` holds an unpushed bump from an earlier ship), it stops
  and tells you to bring the branch up to date first. That includes
  `pushback-unpushed-bump-<build>` branches, where a PR ship from a worktree
  parks its bump commit if the final push is rejected.

### Build artifacts

Every intermediate lives under `<app dir>/build/`: the verify build, the unit
test run, the archive's DerivedData (`build/archive`), the `.xcarchive`, and the
export directory. Each is removed as soon as it's no longer needed, and the
whole `build/` tree is swept on success.

The QA simulator is cleaned up too. If `pushback` booted it, it shuts it down
as soon as the QA gate finishes (pass or fail, Ctrl-C included), so a booted
sim isn't left eating RAM through the archive and after. A simulator that was
already running when you started is yours and is left alone. Set
`PUSHBACK_KEEP_SIM=1` to keep it up.

Give pushback a simulator of its own. If `PUSHBACK_SIM_DEVICE` is unset it
uses the newest runtime's first iPhone, which is probably the one you (or your
coding agent) are already using, and then pushback's QA run and your session
share, boot and shut down the same device. A dedicated one is a single
command:

```bash
xcrun simctl create "pushback QA" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro
```

Put the UDID it prints in `PUSHBACK_SIM_DEVICE`.

Nothing is written to `~/Library/Developer/Xcode/DerivedData`. That matters if
you ship from git worktrees: Xcode keys its default DerivedData location on the
`.xcodeproj` absolute path, so each worktree would otherwise get its own cache
that survives the worktree's deletion. Keeping the cache in `build/` means it
dies with the checkout.

---

## Configuration

`.pushbackrc` is sourced shell. See [`.pushbackrc.example`](.pushbackrc.example)
for every key. Minimal config needs only `PUSHBACK_SCHEME`; everything else
derives from it or has a default.

---

## Development

`pushback` is one bash file that has to run on the bash 3.2 macOS ships. The
test suite runs the real script end to end against stubbed `xcodebuild`,
`xcrun simctl`, `gh`, `xcodegen` and `maestro`, and a throwaway local git
remote. Nothing touches Xcode, your simulators, GitHub, or your git config.

```bash
test/run.sh              # everything (about a minute)
test/run.sh stash lock   # tests whose names contain "stash" or "lock"
```

CI runs it on macOS, plus ShellCheck, for every PR.

---

## License

MIT. See [LICENSE](LICENSE).
