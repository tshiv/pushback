# QA simulator lifecycle and the one-ship-per-repo lock.

t_sim_booted_by_us_is_shut_down() {
    run_pb
    assert_rc 0
    assert_log "xcrun simctl bootstatus $SIM_PRO -b"
    assert_log "xcrun simctl shutdown $SIM_PRO"
    assert_log "maestro --device $SIM_PRO"
    assert_eq "$(sim_state "$SIM_PRO")" Shutdown "sim"
}

t_sim_already_booted_is_left_alone() {
    boot "$SIM_PRO"
    run_pb
    assert_rc 0
    refute_log "simctl bootstatus"
    refute_log "simctl shutdown"
    assert_eq "$(sim_state "$SIM_PRO")" Booted "sim"
}

t_keep_sim_leaves_it_booted() {
    PUSHBACK_KEEP_SIM=1 run_pb
    assert_rc 0
    assert_eq "$(sim_state "$SIM_PRO")" Booted "sim"
}

t_sim_name_picks_newest_runtime() {
    run_pb --dry-run
    assert_rc 0
    assert_out "$SIM_PRO"
    refute_out "$SIM_OLD"
}

t_sim_udid_pins_device() {
    echo "PUSHBACK_SIM_DEVICE=\"$(printf '%s' "$SIM_OLD" | tr 'A-F' 'a-f')\"" >>"$CONFIG"
    run_pb
    assert_rc 0
    assert_log "id=$SIM_OLD"
    assert_eq "$(sim_state "$SIM_OLD")" Shutdown "sim"
}

t_bad_sim_name_fails_before_build() {
    echo 'PUSHBACK_SIM_DEVICE="iPhone 99"' >>"$CONFIG"
    run_pb
    assert_fail
    assert_out 'No available simulator named "iPhone 99"'
    refute_log "xcodebuild"
    assert_no_lock
}

t_skip_qa_never_touches_sims() {
    echo 'PUSHBACK_SIM_DEVICE="iPhone 99"' >>"$CONFIG"
    run_pb --skip-qa
    assert_rc 0
    refute_log "xcrun"
    refute_log "xcodebuild test"
}

t_live_lock_blocks_second_ship() {
    sleep 60 & BG_PIDS=$!
    mkdir "$(lock_dir)" && printf '%s\n%s\n' "$BG_PIDS" "/elsewhere" >"$(lock_dir)/owner"
    run_pb
    assert_fail
    assert_out "Another pushback (pid $BG_PIDS, in /elsewhere)"
    refute_log "xcodebuild"
    [ -d "$(lock_dir)" ] || die "the other run's lock was removed"
}

t_dead_lock_is_taken_over() {
    sh -c 'exit 0' & dead=$!; wait "$dead"
    mkdir "$(lock_dir)" && printf '%s\n%s\n' "$dead" "/elsewhere" >"$(lock_dir)/owner"
    run_pb
    assert_rc 0
    assert_no_lock
}
