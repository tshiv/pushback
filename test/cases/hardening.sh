# Regression tests for the 0.2.0 hardening: burned-build record, signals,
# lock races, leftover bump branches, offline runs, config edge cases.

# ── Signals ────────────────────────────────────────────────────────

t_hangup_mid_archive_reverts() {
    # Closing the terminal tab mid-archive.
    FAKE_SIGNAL_ON_ARCHIVE=HUP run_pb
    assert_rc 129
    assert_out "Reverting uncommitted version bump"
    assert_eq "$(build_in "$T/repo")" 41 "local build"
    assert_no_lock
}

t_interrupt_mid_archive_reverts() {
    FAKE_SIGNAL_ON_ARCHIVE=INT run_pb
    assert_rc 130
    assert_eq "$(build_in "$T/repo")" 41 "local build"
    assert_no_lock
}

# ── Burned build numbers ───────────────────────────────────────────

t_upload_attempt_records_burned_build() {
    FAKE_EXPORT_FAIL=1 run_pb
    assert_fail
    assert_eq "$(burned_for)" 42 "burned record"
}

t_dry_run_records_nothing() {
    run_pb --dry-run
    assert_rc 0
    [ ! -e "$T/repo/.git/pushback.burned" ] || die "dry run recorded a burned build"
}

t_stashing_a_kept_bump_is_refused() {
    # The upload failed, so 42 is kept as an uncommitted edit. Stashing it
    # and shipping HEAD (41) would bump to 42 again.
    FAKE_EXPORT_FAIL=1 run_pb
    assert_fail
    : >"$STUB_LOG"
    run_pb --dirty stash
    assert_fail
    assert_out "Build 42 was already sent to App Store Connect from this clone"
    refute_log "xcodebuild"
    assert_eq "$(build_in "$T/repo")" 42 "kept bump restored from the stash"
    [ -z "$(git -C "$T/repo" stash list)" ] || die "stash entry left behind"
}

t_discarded_kept_bump_is_refused() {
    FAKE_EXPORT_FAIL=1 run_pb
    git -C "$T/repo" checkout -q -- ios
    : >"$STUB_LOG"
    run_pb
    assert_fail
    assert_out "Build 42 was already sent"
    refute_log "xcodebuild"
}

t_committed_kept_bump_ships_past_it() {
    FAKE_EXPORT_FAIL=1 run_pb
    git -C "$T/repo" commit -qam "chore: bump iOS to 1.0.0 (42)"
    git -C "$T/repo" push -q origin HEAD:refs/heads/main 2>/dev/null
    run_pb
    assert_rc 0
    assert_out "Shipped 1.0.0 (43)"
    assert_eq "$(burned_for)" 43 "burned record"
}

t_burned_record_is_shared_by_worktrees() {
    FAKE_EXPORT_FAIL=1 run_pb
    git -C "$T/repo" worktree add -q -b side "$T/side" origin/main 2>/dev/null
    PB_CWD="$T/side" run_pb
    assert_fail
    assert_out "Build 42 was already sent"
}

# ── Dirty trees ────────────────────────────────────────────────────

t_dirty_stash_ships_head_and_restores() {
    echo wip >"$T/repo/notes.txt"
    run_pb --dirty stash
    assert_rc 0
    ! git -C "$T/repo" show --stat HEAD | grep -q notes.txt || die "stashed file was committed"
    [ "$(cat "$T/repo/notes.txt")" = wip ] || die "stashed change not restored"
    [ -z "$(git -C "$T/repo" stash list)" ] || die "stash entry left behind"
    assert_eq "$(remote_build)" 42 "origin/main build"
}

t_dirty_abort_ships_nothing() {
    echo wip >"$T/repo/notes.txt"
    run_pb --dirty abort
    assert_fail
    assert_out "Aborted. Nothing shipped."
    refute_log "xcodebuild"
}

t_dirty_without_tty_or_choice_explains() {
    echo wip >"$T/repo/notes.txt"
    NO_YES=1 run_pb
    assert_fail
    assert_out "--dirty include|stash|abort"
}

t_bad_arguments_exit_2() {
    run_pb --dirty maybe
    assert_rc 2
    run_pb notanumber
    assert_rc 2
    refute_log "xcodebuild"
}

t_include_mode_kept_bump_hint_adds_everything() {
    echo wip >"$T/repo/notes.txt"
    FAKE_EXPORT_FAIL=1 run_pb
    assert_fail
    assert_out "add -A"
    assert_out 'bump\ iOS\ to\ 1.0.0\ \(42\)'
}

# ── Lock races ─────────────────────────────────────────────────────

t_fresh_ownerless_lock_is_treated_as_live() {
    # Another run between its mkdir and its owner write.
    mkdir "$(lock_dir)"
    run_pb
    assert_fail
    assert_out "Another pushback is starting up"
    [ -d "$(lock_dir)" ] || die "the other run's lock was removed"
}

t_old_ownerless_lock_is_taken_over() {
    mkdir "$(lock_dir)"
    touch -t 202001010000 "$(lock_dir)"
    run_pb
    assert_rc 0
    assert_no_lock
}

# ── Simulator default ──────────────────────────────────────────────

t_unset_sim_picks_newest_iphone() {
    grep -v PUSHBACK_SIM_DEVICE "$CONFIG" >"$CONFIG.t" && mv "$CONFIG.t" "$CONFIG"
    run_pb
    assert_rc 0
    assert_log "id=$SIM_PRO"
}

t_sim_runtime_order_is_numeric() {
    printf '%s\n' "18.2|iPhone 17 Pro|$SIM_OLD|Shutdown" "18.10|iPhone 17 Pro|$SIM_PRO|Shutdown" >"$STUB_SIMS"
    run_pb
    assert_rc 0
    assert_log "id=$SIM_PRO"
}

# ── Leftover bump branches ─────────────────────────────────────────

t_rerun_on_bump_branch_is_refused() {
    pr_in_worktree
    FAKE_MOVE_MAIN=1 run_pb
    assert_fail
    assert_out "branch -D pushback-unpushed-bump-42"
    : >"$STUB_LOG"
    run_pb
    assert_fail
    assert_out "holds a bump commit (build 42)"
    assert_out "git push origin HEAD:refs/heads/main"
    refute_log "xcodebuild"
    ! git --git-dir="$T/remote.git" rev-parse -q --verify refs/heads/pushback-unpushed-bump-42 >/dev/null \
        || die "pushed a new remote branch named after the bump branch"
}

t_branch_named_pushback_does_not_block_bump_branch() {
    git -C "$T/repo" branch pushback
    pr_in_worktree
    FAKE_MOVE_MAIN=1 run_pb
    assert_fail
    git -C "$T/repo" rev-parse -q --verify refs/heads/pushback-unpushed-bump-42 >/dev/null \
        || die "no bump branch holds the unpushed commit"
}

t_legacy_bump_branch_still_blocks_reuse() {
    git -C "$T/repo" switch -q -c pushback/unpushed-bump-50
    set_build "$T/repo" 50
    git -C "$T/repo" commit -qam "chore: bump iOS to 1.0.0 (50)"
    git -C "$T/repo" switch -q main
    run_pb
    assert_fail
    assert_out "pushback/unpushed-bump-50 is at 50"
}

t_pr_stale_message_names_origin_main() {
    git -C "$T/repo" switch -q -c pushback-unpushed-bump-50
    set_build "$T/repo" 50
    git -C "$T/repo" commit -qam "chore: bump iOS to 1.0.0 (50)"
    git -C "$T/repo" switch -q main
    pr_in_worktree
    run_pb
    assert_fail
    assert_out "origin/main (which this PR would ship from) is at build 41"
    [ ! -f "$STUB_LOG.merges" ] || die "merged anyway"
}

# ── Offline ────────────────────────────────────────────────────────

t_offline_pr_mode_stops_before_anything() {
    pr_in_repo
    git -C "$T/repo" remote set-url origin "$T/nowhere.git"
    run_pb
    assert_fail
    assert_out "Couldn't fetch origin"
    refute_log "xcodebuild"
    [ ! -f "$STUB_LOG.merges" ] || die "merged while offline"
}

t_offline_from_main_dry_run_warns() {
    git -C "$T/repo" remote set-url origin "$T/nowhere.git"
    run_pb --dry-run
    assert_rc 0
    assert_out "Couldn't fetch origin"
}

# ── Preflight ──────────────────────────────────────────────────────

t_export_destination_must_be_upload() {
    sed 's/<string>upload</<string>export</' "$T/repo/ios/ExportOptions.plist" >"$T/p" && mv "$T/p" "$T/repo/ios/ExportOptions.plist"
    git -C "$T/repo" commit -qam "export only"; git -C "$T/repo" push -q 2>/dev/null
    run_pb
    assert_fail
    assert_out "must set destination=upload (it has 'export')"
    refute_log "xcodebuild"
}

t_missing_bump_script_fails_before_merge() {
    git -C "$T/repo" rm -q ios/bump-version.sh && git -C "$T/repo" commit -qm "rm bump"
    git -C "$T/repo" push -q 2>/dev/null
    pr_in_repo
    run_pb
    assert_fail
    assert_out "Bump script ./bump-version.sh isn't an executable file"
    [ ! -f "$STUB_LOG.merges" ] || die "merged a PR that couldn't be bumped"
}

t_env_file_is_parsed_not_executed() {
    unset APPSTORE_CONNECT_API_KEY_ID APPSTORE_CONNECT_API_ISSUER_ID
    printf '%s\n' 'APPSTORE_CONNECT_API_KEY_ID="TESTKEY"' \
        "APPSTORE_CONNECT_API_ISSUER_ID=\$(touch $T/pwned)" >"$T/repo/.env.local"
    run_pb --dry-run
    assert_rc 0
    [ ! -e "$T/pwned" ] || die ".env.local was executed"
}

t_missing_asc_vars_fail_cleanly() {
    unset APPSTORE_CONNECT_API_KEY_ID APPSTORE_CONNECT_API_ISSUER_ID
    run_pb --dry-run
    assert_fail
    assert_out "APPSTORE_CONNECT_API_KEY_ID not set"
}

t_commit_paths_with_spaces() {
    git -C "$T/repo" mv ios/Demo.xcodeproj "ios/My App.xcodeproj"
    git -C "$T/repo" commit -qm "rename project"; git -C "$T/repo" push -q 2>/dev/null
    echo 'PUSHBACK_PROJECT="My App.xcodeproj"' >>"$CONFIG"
    run_pb
    assert_rc 0
    git -C "$T/repo" show --stat=200 HEAD | grep -q 'My App.xcodeproj/project.pbxproj' \
        || die "bump commit lacks the spaced .xcodeproj"
    assert_clean "$T/repo"
}

t_commit_paths_as_array() {
    echo 'PUSHBACK_COMMIT_PATHS=(ios/project.yml)' >>"$CONFIG"
    run_pb
    assert_rc 0
    ! git -C "$T/repo" show --stat HEAD | grep -q 'project.pbxproj' || die "committed a path not in the array"
}

# ── doctor ─────────────────────────────────────────────────────────

t_doctor_all_good() {
    NO_YES=1 run_pb doctor
    assert_rc 0
    assert_out "Ready to ship."
    assert_out "QA simulator: iPhone 17 Pro (iOS 26.0) $SIM_PRO"
    refute_log "xcodebuild"
    refute_log "bootstatus"
    assert_no_lock
}

t_doctor_lists_every_problem() {
    unset APPSTORE_CONNECT_API_KEY_ID
    sed 's/<string>upload</<string>export</' "$T/repo/ios/ExportOptions.plist" >"$T/p" && mv "$T/p" "$T/repo/ios/ExportOptions.plist"
    echo 'PUSHBACK_SIM_DEVICE="iPhone 99"' >>"$CONFIG"
    FAKE_GH_UNAUTH=1 NO_YES=1 run_pb doctor
    assert_rc 1
    assert_out "APPSTORE_CONNECT_API_KEY_ID not set"
    assert_out "must set destination=upload"
    assert_out 'No available simulator named "iPhone 99"'
    assert_out "gh isn't signed in"
    assert_out "4 problem(s)"
    refute_out "pushback failed"
}

t_doctor_flags_leftover_bump_branch_and_burned() {
    pr_in_worktree
    FAKE_MOVE_MAIN=1 run_pb
    PB_CWD="$T/repo" NO_YES=1 run_pb doctor
    assert_rc 1
    assert_out "Branch pushback-unpushed-bump-42 holds a build-42 bump"
    assert_out "last build sent to App Store Connect from this clone: 42"
}
