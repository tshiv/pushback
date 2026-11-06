# From-main ships, dry runs, and the build-number invariant.

t_from_main_ships_and_pushes_bump() {
    run_pb
    assert_rc 0
    assert_out "Shipped 1.0.0 (42)"
    assert_eq "$(remote_build)" 42 "origin/main build"
    assert_eq "$(build_in "$T/repo")" 42 "local build"
    assert_eq "$(git -C "$T/repo" show -s --format=%s HEAD)" "chore: bump iOS to 1.0.0 (42)" "commit subject"
    git -C "$T/repo" show --stat HEAD | grep -q 'Demo.xcodeproj/project.pbxproj' || die "bump commit lacks the .xcodeproj"
    assert_eq "$(uploads)" 1 "uploads"
    assert_clean "$T/repo"
    [ ! -d "$T/repo/ios/build" ] || die "ios/build left behind"
    assert_no_lock
}

t_dry_run_changes_nothing() {
    run_pb --dry-run
    assert_rc 0
    assert_out "Dry run complete"
    assert_eq "$(remote_build)" 41 "origin/main build"
    assert_eq "$(build_in "$T/repo")" 41 "local build"
    assert_eq "$(uploads)" 0 "uploads"
    refute_log "xcodebuild archive"
    assert_clean "$T/repo"
    assert_eq "$(sim_state "$SIM_PRO")" Shutdown "sim"
    assert_no_lock
}

t_include_mode_commits_dirty_changes() {
    echo "wip" >"$T/repo/notes.txt"
    run_pb
    assert_rc 0
    git -C "$T/repo" show --stat HEAD | grep -q 'notes.txt' || die "bump commit lacks notes.txt"
    assert_clean "$T/repo"
}

t_upload_failure_keeps_bump() {
    FAKE_EXPORT_FAIL=1 run_pb
    assert_fail
    assert_out "may have received the build anyway"
    assert_out "Do NOT revert it"
    assert_eq "$(build_in "$T/repo")" 42 "local build (kept)"
    assert_eq "$(remote_build)" 41 "origin/main build"
    assert_no_lock
}

t_archive_failure_reverts_bump() {
    FAKE_ARCHIVE_FAIL=1 run_pb
    assert_fail
    assert_out "Reverting uncommitted version bump"
    assert_eq "$(build_in "$T/repo")" 41 "local build"
    assert_clean "$T/repo"
    assert_eq "$(uploads)" 0 "uploads"
    assert_no_lock
}

t_archive_failure_keeps_user_project_edits() {
    printf '# my edit\n' >>"$T/repo/ios/project.yml"
    FAKE_ARCHIVE_FAIL=1 run_pb
    assert_fail
    assert_eq "$(build_in "$T/repo")" 41 "local build"
    grep -q '# my edit' "$T/repo/ios/project.yml" || die "the user's own project.yml edit was discarded"
}

t_push_rejected_keeps_commit() {
    FAKE_MOVE_MAIN=1 run_pb
    assert_fail
    assert_out "Bump committed locally but the push failed"
    assert_eq "$(git -C "$T/repo" show -s --format=%s HEAD)" "chore: bump iOS to 1.0.0 (42)" "local HEAD"
    assert_no_lock
}

t_signal_mid_archive_reverts_and_cleans_up() {
    FAKE_SIGNAL_ON_ARCHIVE=TERM run_pb
    assert_fail
    assert_eq "$(build_in "$T/repo")" 41 "local build"
    assert_eq "$(sim_state "$SIM_PRO")" Shutdown "sim"
    assert_no_lock
}

t_build_failure_bumps_nothing() {
    FAKE_BUILD_FAIL=1 run_pb
    assert_fail
    assert_out "iOS build failed"
    assert_eq "$(build_in "$T/repo")" 41 "local build"
    refute_log "bootstatus"
    assert_no_lock
}

t_test_failure_shuts_sim_and_bumps_nothing() {
    FAKE_TEST_FAIL=1 run_pb
    assert_fail
    assert_out "iOS test suite failed"
    assert_eq "$(sim_state "$SIM_PRO")" Shutdown "sim"
    assert_eq "$(build_in "$T/repo")" 41 "local build"
}

t_detached_head_from_main_refused() {
    git -C "$T/repo" checkout -q --detach
    run_pb --from-main
    assert_fail
    assert_out "HEAD is detached"
    refute_log "xcodebuild"
}

t_stale_build_refused() {
    # Local main holds an unpushed bump (43); a worktree cut from origin/main (41)
    # must not bump to 42, which may already be burned.
    set_build "$T/repo" 43
    git -C "$T/repo" commit -qam "chore: bump iOS to 1.0.0 (43)"
    git -C "$T/repo" worktree add -q -b side "$T/side" origin/main 2>/dev/null
    PB_CWD="$T/side" run_pb
    assert_fail
    assert_out "Build number is stale"
    refute_log "xcodebuild build"
}
