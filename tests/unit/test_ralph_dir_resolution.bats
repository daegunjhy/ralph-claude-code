#!/usr/bin/env bats
# Regression tests for #352: ralph_loop.sh:51 clobbered an exported RALPH_DIR
# with a hardcoded ".ralph", even though every sourced lib/*.sh (sourced
# earlier, at lines 38-47) already resolves RALPH_DIR with the env-respecting
# form ("${RALPH_DIR:-.ralph}"). This split main-script state (PROMPT_FILE,
# LOG_DIR, STATUS_FILE, CLAUDE_SESSION_FILE, ...) into ".ralph" while the libs'
# own state (CB_STATE_FILE, SESSION_FILE, QUEUE_FILE, ...) stayed under the
# exported directory.

load '../helpers/test_helper'

PROJECT_ROOT="${BATS_TEST_DIRNAME}/../.."

setup() {
    TEST_DIR="$(mktemp -d "${BATS_TEST_TMPDIR}/ralphdir.XXXXXX")"
    cd "$TEST_DIR"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# Sourcing ralph_loop.sh must not execute the main loop (guarded by the
# `[[ "${BASH_SOURCE[0]}" == "${0}" ]]` check at the bottom of the file), so
# it is safe to source it in a subshell and inspect the resulting variables.
@test "ralph_loop.sh honors an exported RALPH_DIR (not silently reset to .ralph)" {
    mkdir -p "$TEST_DIR/custom-state"
    run bash -c "
        export RALPH_DIR='$TEST_DIR/custom-state'
        source '$PROJECT_ROOT/ralph_loop.sh'
        echo \"RALPH_DIR=\$RALPH_DIR\"
        echo \"PROMPT_FILE=\$PROMPT_FILE\"
        echo \"LOG_DIR=\$LOG_DIR\"
        echo \"CLAUDE_SESSION_FILE=\$CLAUDE_SESSION_FILE\"
    "
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "^RALPH_DIR=$TEST_DIR/custom-state$"
    echo "$output" | grep -q "^PROMPT_FILE=$TEST_DIR/custom-state/PROMPT.md$"
    echo "$output" | grep -q "^LOG_DIR=$TEST_DIR/custom-state/logs$"
    echo "$output" | grep -q "^CLAUDE_SESSION_FILE=$TEST_DIR/custom-state/.claude_session_id$"
}

@test "ralph_loop.sh and lib/response_analyzer.sh agree on the session-id file path" {
    # This is the concrete failure mode: ralph_loop.sh's own CLAUDE_SESSION_FILE
    # (used to decide what to --resume) and response_analyzer.sh's SESSION_FILE
    # (written by store_session_id()) must resolve to the same path, or the
    # main loop resumes a stale/wrong session id that store_session_id() never
    # actually updated.
    mkdir -p "$TEST_DIR/custom-state"
    run bash -c "
        export RALPH_DIR='$TEST_DIR/custom-state'
        source '$PROJECT_ROOT/ralph_loop.sh'
        echo \"CLAUDE_SESSION_FILE=\$CLAUDE_SESSION_FILE\"
        echo \"SESSION_FILE=\$SESSION_FILE\"
    "
    [ "$status" -eq 0 ]
    local claude_session_file session_file
    claude_session_file=$(echo "$output" | grep '^CLAUDE_SESSION_FILE=' | cut -d= -f2-)
    session_file=$(echo "$output" | grep '^SESSION_FILE=' | cut -d= -f2-)
    [ -n "$claude_session_file" ]
    [ "$claude_session_file" = "$session_file" ]
}

@test "ralph_loop.sh still defaults to .ralph when RALPH_DIR is unset" {
    run bash -c "
        unset RALPH_DIR
        source '$PROJECT_ROOT/ralph_loop.sh'
        echo \"RALPH_DIR=\$RALPH_DIR\"
    "
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "^RALPH_DIR=\.ralph$"
}
