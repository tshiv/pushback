#!/bin/bash
# pushback's test suite: end-to-end runs of the real script against stubbed
# Apple tooling and a throwaway git remote.
#
#   test/run.sh              run every test
#   test/run.sh stash lock   run tests whose name contains "stash" or "lock"
#
# PUSHBACK_TEST_BASH picks the bash to run pushback under (default /bin/bash,
# which on macOS is the 3.2 that users have).
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
# shellcheck source=test/lib.sh
. "$ROOT/test/lib.sh"
for f in "$ROOT"/test/cases/*.sh; do
    # shellcheck disable=SC1090
    . "$f"
done

[ -x "$BASH_BIN" ] || { echo "PUSHBACK_TEST_BASH: no executable bash at $BASH_BIN" >&2; exit 2; }

tests="$(declare -F | awk '$3 ~ /^t_/ {print $3}')"
if [ $# -gt 0 ]; then
    pat="$(printf '%s|' "$@")"; pat="${pat%|}"
    tests="$(printf '%s\n' "$tests" | grep -E -- "$pat" || true)"
fi
[ -n "$tests" ] || { echo "no tests match: $*" >&2; exit 2; }

pass=0; failed=""
for t in $tests; do
    if ( setup; "$t"; rc=$?; [ "$rc" = 0 ] && teardown; exit "$rc" ) >"${TMPDIR:-/tmp}/pushback-test.last" 2>&1; then
        pass=$((pass + 1)); printf '  ok    %s\n' "$t"
    else
        failed="$failed $t"; printf '  FAIL  %s\n' "$t"
        sed 's/^/  /' "${TMPDIR:-/tmp}/pushback-test.last"
    fi
done
rm -f "${TMPDIR:-/tmp}/pushback-test.last"

n_fail=$(printf '%s' "$failed" | wc -w | tr -d ' ')
echo
echo "  $pass passed, $n_fail failed"
[ "$n_fail" = 0 ]
