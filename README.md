# pushback

**From the gate to the App Store, in one command.** Ship an iOS app to
TestFlight from your laptop — no CI, no Ruby, no Fastlane setup tax.

```bash
pushback            # auto-detects: open PR → merge & ship, else ship current branch
pushback --dry-run  # rehearse the whole thing — no merge, no upload, no push
```

`pushback` is a single, dependency-light bash script that does the entire
release in one pass:

**verify build → QA gate → (merge PR) → bump version → archive → upload → commit & push.**

The name is the joke and the spec: in aviation, *pushback* is the tug easing
the plane off the gate — the first move of departure. And it's what you do to
ship: `git push`, then watch it go.

---

## Why not Fastlane?

Fastlane is great — for teams of three sharing certificates (`match`), for
automating App Store metadata and screenshots, and for running inside CI. If
that's you, use Fastlane.

`pushback` is for the other case: **one app, one person, shipping from a
laptop, no CI.** There, Fastlane is mostly setup tax for features you don't
use, and you *still* end up writing glue for the parts it doesn't cover — like
merging the right PR or running a smoke test before `main` is touched.
`pushback` is that glue, made first-class:

- **PR-aware.** Detects the open PR for your branch, checks your local HEAD
  matches it, and verifies the build *before* the squash-merge — a broken iOS
  build can't land in `main`.
- **Ships from `main` too.** No PR? Already merged? It ships the current
  branch's actual state, including uncommitted changes if you want.
- **Pre-merge QA gate.** Unit/snapshot tests, plus Maestro smoke flows if
  installed, before anything irreversible happens.
- **Smart rollback.** Knows the one thing you must never do — revert a build
  number *after* the upload burned it in App Store Connect — and never does it.
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
- [`xcbeautify`](https://github.com/cpisciotta/xcbeautify) — prettier build output (`brew install xcbeautify`)
- [`maestro`](https://maestro.mobile.dev) — UI smoke flows in the QA gate

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

Then run it (point `--config` at your `.pushbackrc`, or drop a `.pushbackrc`
next to the binary / in the working directory):

```bash
pushback --config ios/.pushbackrc --dry-run
```

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
| `pushback --config <path>` | Point at a specific `.pushbackrc` (default: `./.pushbackrc`). |

### Modes

**PR mode** — there's an open PR for the current branch (or you passed a PR
number). `pushback` verifies the build on the PR branch, runs QA,
squash-merges, pulls `main`, then ships. Requires a clean working tree (you're
shipping the PR's code).

**From-main mode** — no open PR; you're on `main` (already merged) or a local
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
only committed HEAD and restores your changes afterward — and never drops the
stash on a conflict.

Both modes show a one-line summary and ask for confirmation before the
irreversible archive+upload. `--yes` skips the prompts.

### The build-number invariant

Once `-exportArchive` succeeds, the bumped build number is **burned** in App
Store Connect — reusing it fails validation. So `pushback`'s failure handler:

- reverts the bump if it failed **before** the upload,
- **leaves the bump in place** and tells you to commit manually if the upload
  succeeded but the commit/push failed,
- tells you to just push if the commit landed but the push failed.

It never reverts a burned build number.

---

## Configuration

`.pushbackrc` is sourced shell. See [`.pushbackrc.example`](.pushbackrc.example)
for every key. Minimal config needs only `PUSHBACK_SCHEME`; everything else
derives from it or has a default.

---

## License

MIT — see [LICENSE](LICENSE).
