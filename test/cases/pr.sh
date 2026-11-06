# PR mode: verify, merge, sync main, ship.

t_pr_mode_in_repo() {
    pr_in_repo
    run_pb
    assert_rc 0
    assert_out "Shipped 1.0.0 (42)"
    assert_eq "$(remote_build)" 42 "origin/main build"
    git --git-dir="$T/remote.git" log --format=%s main | grep -q "squash: PR #7" || die "PR not merged into main"
    assert_eq "$(git -C "$T/repo" branch --show-current)" main "branch after ship"
    ! git --git-dir="$T/remote.git" rev-parse -q --verify refs/heads/feat >/dev/null || die "origin/feat not deleted"
    ! git -C "$T/repo" rev-parse -q --verify refs/heads/feat >/dev/null || die "local feat not deleted"
    assert_clean "$T/repo"
}

t_pr_mode_from_worktree() {
    pr_in_worktree
    run_pb
    assert_rc 0
    assert_out "detached at the shipped commit"
    assert_eq "$(remote_build)" 42 "origin/main build"
    ! git --git-dir="$T/remote.git" rev-parse -q --verify refs/heads/feat >/dev/null || die "origin/feat not deleted"
    ! git -C "$T/repo" rev-parse -q --verify refs/heads/feat >/dev/null || die "local feat not deleted"
    [ -z "$(git -C "$T/repo" for-each-ref refs/heads/pushback/ refs/heads/pushback-unpushed-bump-*)" ] \
        || die "bump branch left after a successful push"
    assert_no_lock
}

t_pr_fork_head_branch_is_never_deleted() {
    # A fork PR whose head branch is named "main": deleting it "on origin"
    # would delete our main.
    pr_in_repo
    FAKE_CROSS=true FAKE_HEAD_REF=main run_pb
    assert_rc 0
    assert_out "lives in a fork"
    git --git-dir="$T/remote.git" rev-parse -q --verify refs/heads/main >/dev/null || die "origin/main deleted"
}

t_pr_dirty_tree_refused() {
    pr_in_repo
    echo junk >"$T/repo/junk.txt"
    run_pb
    assert_fail
    assert_out "Working tree is dirty"
    refute_log "xcodebuild"
}

t_pr_head_mismatch_refused() {
    pr_in_repo
    commit_file "$T/repo" unpushed.txt
    run_pb
    assert_fail
    assert_out "Local HEAD"
    [ ! -f "$STUB_LOG.merges" ] || die "merged anyway"
}

t_pr_build_failure_merges_nothing() {
    pr_in_repo
    FAKE_BUILD_FAIL=1 run_pb
    assert_fail
    [ ! -f "$STUB_LOG.merges" ] || die "merged a PR whose build failed"
}

t_pr_diverged_main_refused_before_merge() {
    # Local main has an unpushed commit, so it can't fast-forward after the merge.
    commit_file "$T/repo" local-only.txt
    pr_in_repo
    run_pb
    assert_fail
    assert_out "Nothing was merged"
    [ ! -f "$STUB_LOG.merges" ] || die "merged anyway"
}

t_pr_detached_push_rejected_keeps_bump_on_a_branch() {
    pr_in_worktree
    FAKE_MOVE_MAIN=1 run_pb
    assert_fail
    assert_out "push failed"
    b="$(git -C "$T/repo" for-each-ref --format='%(refname:short)' refs/heads/pushback/ 'refs/heads/pushback-unpushed-bump-*')"
    [ -n "$b" ] || die "no branch holds the unpushed bump commit"
    assert_eq "$(build_at_ref "$T/repo" "$b")" 42 "build on $b"
}
