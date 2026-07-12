#!/usr/bin/env bash
#
# go-org/mayhem/test.sh — RUN niklasfasching/go-org's OWN Go test suite and emit a CTRF summary.
# exit 0 iff no test failed.
#
# PATCH-grade oracle: go-org's suite is a REAL golden-file suite — org/org_writer_test.go and
# org/html_writer_test.go render every org/testdata/*.org fixture and byte-compare the output
# against the checked-in .golden .org/.html files; org/util_test.go asserts ParseRanges/
# TopLevelHLevel/PrettyRelativeLinks known-answer results; blorg/config_test.go builds the
# example blog and compares every generated file against blorg/testdata/public. They assert
# BEHAVIOUR, not "exits 0", so a no-op patch FAILS this oracle.
#
# Anti-reward-hack (SPEC §6.3): go-org is pure Go — its compiled test binaries are statically
# linked and LD_PRELOAD cannot intercept them. We run the suite through mayhem-build/test-runner,
# a thin dynamically-linked C shim (built by build.sh) that exec()s `go test -json -count=1`.
# The sabotage check (LD_PRELOAD _exit(0) for non-system binaries) intercepts the C shim, which
# never exec()s go → no output → fewer tests counted → sabotage detected.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SRC:=/mayhem}"
export PATH="/opt/toolchains/go/bin:/opt/toolchains/go-path/bin:/usr/local/bin:/usr/bin:/bin"
export GOFLAGS="${GOFLAGS:--mod=mod}"
export GOTOOLCHAIN="${GOTOOLCHAIN:-local}"
export GOMODCACHE="${GOMODCACHE:-/opt/toolchains/go-path/pkg/mod}"
export GOCACHE="${GOCACHE:-/opt/toolchains/go-path/build-cache}"
export GOPROXY="${GOPROXY:-file://${GOMODCACHE}/cache/download,https://proxy.golang.org,direct}"
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

RUNNER="$SRC/mayhem-build/test-runner"
JSON="$SRC/mayhem-build/gotest.json"
mkdir -p "$SRC/mayhem-build"

if [ ! -x "$RUNNER" ]; then
  echo "FATAL: $RUNNER missing — mayhem/build.sh should have built it" >&2
  emit_ctrf "go-test" 0 1 0
  exit 1
fi

echo "=== running: test-runner (go test -json -count=1 ./org ./blorg shim) ==="
"$RUNNER" > "$JSON" 2>"$SRC/mayhem-build/gotest.err"; rc=$?
[ -s "$SRC/mayhem-build/gotest.err" ] && { echo "--- stderr ---"; tail -5 "$SRC/mayhem-build/gotest.err"; }

# Count TOP-LEVEL test results from the go test -json event stream (skip subtests so the
# counts are stable across fixture additions upstream; a package-level build failure with
# no test events still yields failed>0 via the rc fallback below).
counts=$(python3 - "$JSON" <<'PYEOF'
import json, sys
passed = failed = skipped = 0
with open(sys.argv[1]) as f:
    for line in f:
        try:
            ev = json.loads(line)
        except Exception:
            continue
        t = ev.get("Test")
        if not t or "/" in t:
            continue
        a = ev.get("Action")
        if a == "pass": passed += 1
        elif a == "fail": failed += 1
        elif a == "skip": skipped += 1
        if a in ("pass", "fail", "skip"):
            print(a.upper(), t, file=sys.stderr)
print(passed, failed, skipped)
PYEOF
)
read -r passed failed skipped <<<"$counts"
: "${passed:=0}" "${failed:=0}" "${skipped:=0}"

# A crashed/silent runner may report 0 failures in the stream — count it as a failure.
if [ "$rc" -ne 0 ] && [ "$failed" -eq 0 ]; then failed=1; fi

emit_ctrf "go-test" "$passed" "$failed" "$skipped"
