# Regression tests for the 0.2.0 review: cleanup that survives a closed
# terminal or a second Ctrl-C, foreground xcodebuild, per-app burned records,
# and the edge cases around them.

# ── A real terminal ────────────────────────────────────────────────

t_terminal_closed_mid_archive_reverts() {
    start_pb_in_pty
    kill -KILL "$PTY_PID"          # the window goes away: SIGHUP, then EIO on every write
    wait_pb_gone
    assert_eq "$(build_in "$T/repo")" 41 "local build"
    assert_no_lock
}

t_terminal_closed_mid_archive_restores_stash() {
    echo wip >"$T/repo/notes.txt"
    start_pb_in_pty --dirty stash
    kill -KILL "$PTY_PID"
    wait_pb_gone
    [ "$(cat "$T/repo/notes.txt" 2>/dev/null)" = wip ] || die "stashed work not restored"
    [ -z "$(git -C "$T/repo" stash list)" ] || die "stash entry left behind"
    assert_eq "$(build_in "$T/repo")" 41 "local build"
    assert_no_lock
}

t_ctrl_c_in_terminal_stops_xcodebuild_too() {
    start_pb_in_pty
    pg="$(ps -o pgid= -p "$PB_PID" | tr -d ' ')"
    kill -INT -- "-$pg"            # Ctrl-C: the terminal signals the whole foreground group
    wait_pb_gone
    sleep "$((FAKE_SLOW_ARCHIVE + 1))"
    [ ! -e "$STUB_LOG.archive_done" ] || die "xcodebuild archive outlived pushback"
    assert_eq "$(build_in "$T/repo")" 41 "local build"
    assert_no_lock
    kill "$PTY_PID" 2>/dev/null || true   # usually already gone with its session
}

# ── Signals at other points ────────────────────────────────────────

t_ctrl_c_during_cleanup_still_finishes_it() {
    echo wip >"$T/repo/notes.txt"
    FAKE_TEST_FAIL=1 FAKE_SIGNAL_ON_SHUTDOWN=INT run_pb --dirty stash
    assert_fail
    assert_out "pushback failed"
    [ "$(cat "$T/repo/notes.txt")" = wip ] || die "stashed work not restored"
    [ -z "$(git -C "$T/repo" stash list)" ] || die "stash entry left behind"
    assert_no_lock
}

t_signal_during_qa_shuts_down_sim() {
    FAKE_SIGNAL_ON_TEST=TERM run_pb
    assert_rc 143
    assert_log "simctl shutdown $SIM_PRO"
    assert_eq "$(sim_state "$SIM_PRO")" Shutdown "sim"
    assert_no_lock
}

t_signal_during_upload_keeps_bump() {
    FAKE_SIGNAL_ON_EXPORT=TERM run_pb
    assert_rc 143
    assert_out "Do NOT revert it"
    assert_eq "$(build_in "$T/repo")" 42 "local build (kept)"
    assert_eq "$(burned_for)" 42 "burned record"
}

t_stash_mode_upload_failure_keeps_bump_and_restores() {
    echo wip >"$T/repo/notes.txt"
    FAKE_EXPORT_FAIL=1 run_pb --dirty stash
    assert_fail
    assert_eq "$(build_in "$T/repo")" 42 "local build (kept)"
    [ "$(cat "$T/repo/notes.txt")" = wip ] || die "stashed work not restored"
}

# ── Burned record, lock ────────────────────────────────────────────

t_burned_record_is_per_app() {
    printf 'watch/project.yml\t99\n' >"$T/repo/.git/pushback.burned"
    run_pb
    assert_rc 0
    assert_eq "$(burned_for)" 42 "ios burned record"
    assert_eq "$(burned_for watch/project.yml)" 99 "other app's record kept"
}

t_lock_held_by_unsignalable_pid_is_live() {
    # pid 1 is alive but not ours to signal: kill -0 says EPERM.
    mkdir "$(lock_dir)" && printf '1\n/elsewhere\n' >"$(lock_dir)/owner"
    run_pb
    assert_fail
    assert_out "Another pushback (pid 1, in /elsewhere)"
    [ -d "$(lock_dir)" ] || die "the lock was taken over"
}

# ── Preflight and arguments ────────────────────────────────────────

t_missing_build_field_is_reported() {
    grep -v CURRENT_PROJECT_VERSION "$T/repo/ios/project.yml" >"$T/p" && mv "$T/p" "$T/repo/ios/project.yml"
    git -C "$T/repo" commit -qam "no build"
    run_pb
    assert_fail
    assert_out "Couldn't read MARKETING_VERSION and an integer CURRENT_PROJECT_VERSION"
    NO_YES=1 run_pb doctor
    assert_rc 1
    assert_out "Couldn't read MARKETING_VERSION"
    assert_out "problem(s)"
}

t_flag_without_value_exits_2() {
    run_pb --dirty
    assert_rc 2
    assert_out "--dirty needs a value"
    run_pb --config
    assert_rc 2
}

t_empty_commit_paths_array_exits_2() {
    echo 'PUSHBACK_COMMIT_PATHS=()' >>"$CONFIG"
    run_pb
    assert_rc 2
    assert_out "PUSHBACK_COMMIT_PATHS is empty"
}

t_quoted_env_value_with_comment() {
    unset APPSTORE_CONNECT_API_KEY_ID APPSTORE_CONNECT_API_ISSUER_ID
    printf '%s\n' 'APPSTORE_CONNECT_API_KEY_ID="TESTKEY" # prod key' \
        "APPSTORE_CONNECT_API_ISSUER_ID='test-issuer'  # team" >"$T/repo/.env.local"
    run_pb --dirty stash   # .env.local is untracked; keep it out of the commit
    assert_rc 0
    assert_log "-authenticationKeyID TESTKEY -authenticationKeyIssuerID test-issuer"
}

t_pr_url_argument() {
    pr_in_repo
    run_pb https://github.com/example/demo/pull/7
    assert_rc 0
    assert_out "pr #7 → main"
}

# ── PR detection ───────────────────────────────────────────────────

t_gh_failure_on_branch_refuses_to_guess() {
    pr_in_repo
    FAKE_GH_UNAUTH=1 run_pb
    assert_fail
    assert_out "gh couldn't check whether feat has an open PR"
    refute_log "xcodebuild"
    assert_eq "$(build_at_ref "$T/remote.git" feat)" 41 "origin/feat build"
}

t_branch_without_pr_ships_from_it() {
    git -C "$T/repo" switch -q -c side
    git -C "$T/repo" push -q -u origin side 2>/dev/null
    run_pb
    assert_rc 0
    assert_out "side → testflight"
    assert_eq "$(build_at_ref "$T/remote.git" side)" 42 "origin/side build"
}

# ── Commit contents ────────────────────────────────────────────────

t_untracked_commit_path_still_reverts() {
    echo 'PUSHBACK_COMMIT_PATHS="ios/project.yml ios/Generated.xcodeproj/"' >>"$CONFIG"
    FAKE_ARCHIVE_FAIL=1 run_pb
    assert_fail
    assert_eq "$(build_in "$T/repo")" 41 "local build"
}

t_include_mode_never_commits_build_dir() {
    : >"$T/repo/.gitignore"
    git -C "$T/repo" commit -qam "ignore nothing"; git -C "$T/repo" push -q 2>/dev/null
    echo wip >"$T/repo/notes.txt"
    run_pb
    assert_rc 0
    ! git -C "$T/repo" show --stat=200 HEAD | grep -q 'ios/build' || die "committed ios/build"
}

# ── doctor ─────────────────────────────────────────────────────────

t_doctor_changes_nothing() {
    # FETCH_HEAD aside: doctor fetches origin, and that's all it may write.
    snapshot() {
        git -C "$T/repo" for-each-ref refs/heads refs/tags
        git -C "$T/repo" status --porcelain
        find "$T/repo/.git" -maxdepth 1 ! -name FETCH_HEAD | sort
    }
    before="$(snapshot)"
    NO_YES=1 run_pb doctor
    assert_rc 0
    after="$(snapshot)"
    assert_eq "$after" "$before" "repo state"
    assert_eq "$(sim_state "$SIM_PRO")" Shutdown "sim"
}

t_doctor_bump_branch_already_pushed_is_a_warning() {
    git -C "$T/repo" branch pushback-unpushed-bump-41
    NO_YES=1 run_pb doctor
    assert_rc 0
    assert_out "branch pushback-unpushed-bump-41 is already on origin/main"
}

# ── Round 2 ────────────────────────────────────────────────────────

t_tracked_build_dir_is_left_alone() {
    mkdir -p "$T/repo/ios/build" && echo keep >"$T/repo/ios/build/README"
    git -C "$T/repo" add -f ios/build/README && git -C "$T/repo" commit -qm "track build/README"
    git -C "$T/repo" push -q 2>/dev/null
    echo wip >"$T/repo/notes.txt"
    run_pb
    assert_rc 0
    [ -f "$T/repo/ios/build/README" ] || die "tracked ios/build/README was deleted"
    git --git-dir="$T/remote.git" cat-file -e main:ios/build/README 2>/dev/null || die "the bump commit deleted ios/build/README"
}

t_bump_that_does_not_raise_build_is_refused() {
    printf '#!/bin/bash\nexit 0\n' >"$T/repo/ios/bump-version.sh"
    git -C "$T/repo" commit -qam "no-op bump"; git -C "$T/repo" push -q 2>/dev/null
    run_pb
    assert_fail
    assert_out "left the build at '41'"
    refute_log "xcodebuild archive"
    assert_eq "$(uploads)" 0 "uploads"
}

t_burned_key_is_normalized() {
    echo 'PUSHBACK_APP_DIR="./ios/"' >>"$CONFIG"
    FAKE_EXPORT_FAIL=1 run_pb
    assert_fail
    git -C "$T/repo" checkout -q -- ios
    sed '/PUSHBACK_APP_DIR/d' "$CONFIG" >"$CONFIG.t" && mv "$CONFIG.t" "$CONFIG"
    run_pb
    assert_fail
    assert_out "Build 42 was already sent"
}

t_success_writes_no_stray_carriage_return() {
    run_pb
    assert_rc 0
    ! grep -q "$(printf '\r')" "$T/out" || die "stray carriage return in non-TTY output"
}

t_pr_bump_that_does_not_raise_build_says_pr_is_merged() {
    printf '#!/bin/bash\nexit 0\n' >"$T/repo/ios/bump-version.sh"
    git -C "$T/repo" commit -qam "no-op bump"; git -C "$T/repo" push -q 2>/dev/null
    pr_in_repo
    run_pb
    assert_fail
    assert_out "PR #7 is merged, but nothing was bumped or uploaded."
    assert_out "left the build at '41'"
    assert_eq "$(uploads)" 0 "uploads"
}
