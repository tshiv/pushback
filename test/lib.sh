# Test helpers, sourced by test/run.sh. Each test runs in a subshell with its
# own scratch dir $T:
#   $T/remote.git  bare "origin"
#   $T/repo        a clone on main holding a tiny ios/ app at build 41
#   $T/bin         the stubs in test/stubs, first on PATH
#   $T/out         combined output of the last run_pb
# Nothing touches the real Xcode, simulators, GitHub or your git config.

PUSHBACK="$ROOT/pushback"
# macOS ships bash 3.2 as /bin/bash, which is what pushback must run on.
BASH_BIN="${PUSHBACK_TEST_BASH:-/bin/bash}"

SIM_PRO="AAAAAAAA-0000-4000-8000-000000000001"   # iPhone 17 Pro, iOS 26.0
SIM_OLD="AAAAAAAA-0000-4000-8000-000000000002"   # iPhone 17 Pro, iOS 18.0
SIM_AIR="AAAAAAAA-0000-4000-8000-000000000003"   # iPhone Air,    iOS 26.0

setup() {
    T="$(mktemp -d "${TMPDIR:-/tmp}/pushback-test.XXXXXX")"
    T="$(cd "$T" && pwd -P)"
    export HOME="$T/home" GIT_CONFIG_NOSYSTEM=1
    mkdir -p "$HOME"
    cat >"$HOME/.gitconfig" <<'EOF'
[user]
    name = pushback test
    email = test@example.com
[init]
    defaultBranch = main
[commit]
    gpgsign = false
[advice]
    detachedHead = false
EOF
    cp -R "$ROOT/test/stubs" "$T/bin"
    export PATH="$T/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    export STUB_LOG="$T/stub.log" STUB_SIMS="$T/sims" FAKE_REMOTE="$T/remote.git" STUB_TMP="$T/tmp"
    : >"$STUB_LOG"; mkdir -p "$STUB_TMP"
    printf '%s\n' \
        "26.0|iPhone 17 Pro|$SIM_PRO|Shutdown" \
        "18.0|iPhone 17 Pro|$SIM_OLD|Shutdown" \
        "26.0|iPhone Air|$SIM_AIR|Shutdown" >"$STUB_SIMS"
    unset NO_COLOR SKIP_PRE_SHIP_QA PUSHBACK_KEEP_SIM
    export APPSTORE_CONNECT_API_KEY_ID=TESTKEY APPSTORE_CONNECT_API_ISSUER_ID=test-issuer
    mkdir -p "$T/keys" && : >"$T/keys/AuthKey_TESTKEY.p8"

    git init -q --bare "$T/remote.git"
    git clone -q "$T/remote.git" "$T/repo" 2>/dev/null
    mkdir -p "$T/repo/ios/Demo.xcodeproj"
    cat >"$T/repo/ios/project.yml" <<'EOF'
name: Demo
settings:
  MARKETING_VERSION: "1.0.0"
  CURRENT_PROJECT_VERSION: 41
EOF
    echo "CURRENT_PROJECT_VERSION = 41;" >"$T/repo/ios/Demo.xcodeproj/project.pbxproj"
    cat >"$T/repo/ios/bump-version.sh" <<'EOF'
#!/bin/bash
set -e
b="$(awk '/CURRENT_PROJECT_VERSION:/ {print $2}' project.yml)"
awk -v n="$((b + 1))" '/CURRENT_PROJECT_VERSION:/ {sub(/[0-9]+$/, n)} {print}' project.yml >project.yml.tmp
mv project.yml.tmp project.yml
EOF
    chmod +x "$T/repo/ios/bump-version.sh"
    cat >"$T/repo/ios/ExportOptions.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>destination</key>
    <string>upload</string>
    <key>method</key>
    <string>app-store-connect</string>
</dict>
</plist>
EOF
    mkdir -p "$T/repo/ios/maestro"
    echo "appId: com.example.demo" >"$T/repo/ios/maestro/smoke.yaml"
    # Outside the repo, so tests that edit it don't dirty the tree.
    cat >"$T/pushbackrc" <<EOF
PUSHBACK_SCHEME="Demo"
PUSHBACK_SIM_DEVICE="iPhone 17 Pro"
PUSHBACK_ASC_KEY_DIR="$T/keys"
EOF
    printf 'ios/build/\n' >"$T/repo/.gitignore"
    git -C "$T/repo" add -A
    git -C "$T/repo" commit -qm "init"
    git -C "$T/repo" push -q -u origin main 2>/dev/null
    CONFIG="$T/pushbackrc"
}

teardown() {
    # Reap anything a test left running (lock-holder sleeps, etc.).
    [ -z "${BG_PIDS:-}" ] || kill "$BG_PIDS" 2>/dev/null
    rm -rf "$T"
}

# run_pb [args...]: run pushback from $PB_CWD (default the main checkout).
# Sets RC; output lands in $T/out. --yes is added unless NO_YES=1.
run_pb() {
    local yes="--yes"; [ "${NO_YES:-0}" = 1 ] && yes=""
    # shellcheck disable=SC2086
    (cd "${PB_CWD:-$T/repo}" && "$BASH_BIN" "$PUSHBACK" --config "$CONFIG" $yes "$@") \
        >"$T/out" 2>&1 </dev/null
    RC=$?
}

# start_pb_in_pty [args...]: start pushback in the background inside a
# pseudo-terminal, as from a real terminal window, with FAKE_SLOW_ARCHIVE set
# so it sits in the archive step. Returns once the archive has started, with
# PTY_PID (the `script` process that owns the terminal) and PB_PID set. Kill
# PTY_PID to close the "window"; signal -PB_PID's group for a Ctrl-C.
start_pb_in_pty() {
    export FAKE_SLOW_ARCHIVE="${FAKE_SLOW_ARCHIVE:-6}"
    # Job control on: without it this background job, and everything under
    # it, starts with SIGINT ignored, and a Ctrl-C test would test nothing.
    set -m
    (cd "${PB_CWD:-$T/repo}" && exec script -q /dev/null "$BASH_BIN" "$PUSHBACK" --config "$CONFIG" --yes "$@") \
        </dev/null >"$T/out" 2>&1 &
    # shellcheck disable=SC2034  # read by the tests
    PTY_PID=$!
    set +m
    local _
    for _ in $(seq 1 100); do [ -s "$STUB_LOG.pbpid" ] && break; sleep 0.1; done
    PB_PID="$(cat "$STUB_LOG.pbpid" 2>/dev/null)"
    [ -n "$PB_PID" ] || die "pushback never reached the archive step"
}

wait_pb_gone() {   # wait (up to 15s) for PB_PID to exit
    local _
    for _ in $(seq 1 150); do kill -0 "$PB_PID" 2>/dev/null || return 0; sleep 0.1; done
    die "pushback (pid $PB_PID) still running"
}

# ── Fixture helpers ────────────────────────────────────────────────

commit_file() {   # commit_file <dir> <file> [content]
    echo "${3:-$2}" >"$1/$2"
    git -C "$1" add -A && git -C "$1" commit -qm "add $2"
}

set_build() {     # set_build <dir> <n>: rewrite the build number in <dir>/ios/project.yml
    awk -v n="$2" '/CURRENT_PROJECT_VERSION:/ {sub(/[0-9]+$/, n)} {print}' \
        "$1/ios/project.yml" >"$1/ios/project.yml.tmp" && mv "$1/ios/project.yml.tmp" "$1/ios/project.yml"
}

# A PR branch "feat" pushed to origin, checked out in a separate worktree
# ($T/wt) while main stays checked out in $T/repo. Runs then happen from $T/wt.
pr_in_worktree() {
    git -C "$T/repo" worktree add -q -b feat "$T/wt" 2>/dev/null
    commit_file "$T/wt" feature.txt
    git -C "$T/wt" push -q -u origin feat 2>/dev/null
    export FAKE_PR=1 FAKE_PR_BRANCH=feat
    PB_CWD="$T/wt"
}

# Same, but on a branch in the main checkout itself (no worktree).
pr_in_repo() {
    git -C "$T/repo" switch -q -c feat
    commit_file "$T/repo" feature.txt
    git -C "$T/repo" push -q -u origin feat 2>/dev/null
    export FAKE_PR=1 FAKE_PR_BRANCH=feat
}

# ── Queries ────────────────────────────────────────────────────────

build_in() { awk '/CURRENT_PROJECT_VERSION:/ {print $2; exit}' "$1/ios/project.yml"; }
build_at_ref() {  # build_at_ref <git-dir-or-checkout> <ref>
    git -C "$1" show "$2:ios/project.yml" 2>/dev/null | awk '/CURRENT_PROJECT_VERSION:/ {print $2; exit}'
}
remote_build() { git --git-dir="$T/remote.git" show main:ios/project.yml | awk '/CURRENT_PROJECT_VERSION:/ {print $2; exit}'; }
sim_state() { awk -F'|' -v id="$1" '$3 == id {print $4}' "$STUB_SIMS"; }
boot() { awk -F'|' -v OFS='|' -v id="$1" '$3 == id {$4 = "Booted"} {print}' "$STUB_SIMS" >"$STUB_SIMS.t" && mv "$STUB_SIMS.t" "$STUB_SIMS"; }
lock_dir() { echo "$T/repo/.git/pushback.lock"; }
burned_for() {   # burned_for [app-key]: this clone's burned record for an app
    awk -F'\t' -v k="${1:-ios/project.yml}" '$1 == k {print $2}' "$T/repo/.git/pushback.burned" 2>/dev/null
}
uploads() { [ -f "$STUB_LOG.uploads" ] && grep -c . "$STUB_LOG.uploads" || echo 0; }

# ── Assertions ─────────────────────────────────────────────────────
# Any failed assertion ends the test (it runs in a subshell) and prints the
# pushback output it was looking at.

die() {
    printf '    %s\n' "$@"
    if [ -s "$T/out" ]; then
        echo "    --- pushback output ---"
        sed 's/^/    | /' "$T/out"
    fi
    echo "    (scratch dir kept: $T)"
    exit 1
}
assert_rc()     { [ "$RC" = "$1" ] || die "exit code $RC, expected $1"; }
assert_fail()   { [ "$RC" != 0 ] || die "expected failure, got exit 0"; }
assert_out()    { grep -qF -- "$1" "$T/out" || die "output lacks: $1"; }
refute_out()    { ! grep -qF -- "$1" "$T/out" || die "output unexpectedly has: $1"; }
assert_eq()     { [ "$1" = "$2" ] || die "${3:-value}: got '$1', expected '$2'"; }
assert_log()    { grep -qF -- "$1" "$STUB_LOG" || die "no stub call matching: $1"; }
refute_log()    { ! grep -qF -- "$1" "$STUB_LOG" || die "unexpected stub call: $1"; }
assert_clean()  { [ -z "$(git -C "$1" status --porcelain)" ] || die "tree $1 is dirty:" "$(git -C "$1" status --short)"; }
assert_no_lock() { [ ! -e "$(lock_dir)" ] || die "ship lock left behind at $(lock_dir)"; }
