#!/usr/bin/env bash
#
# go-org/mayhem/build.sh — build niklasfasching/go-org's UPSTREAM go-fuzz harness
# (org/fuzz.go, legacy `func Fuzz([]byte) int`, build tag gofuzz) as a sanitized
# libFuzzer binary, replicating OSS-Fuzz's compile_go_fuzzer path
# (go114-fuzz-build wrapper + clang $LIB_FUZZING_ENGINE link).
#
# Fuzzed surface: org.Parse (the org-mode parser) plus the OrgWriter/HTMLWriter
# round-trip differential check upstream ships in the harness (a mismatch panics —
# a real correctness oracle, not just a crash harness).
#
# Target: /mayhem/go-org-org-fuzz (preserves the old Mayhemfile `target:` name
# go-org-org-fuzz for corpus/defect continuity).
#
# DWARF gate (SPEC §6.2 item 10): Go's gc compiler always emits DWARF4 (no downgrade
# flag). The C shim compiled by clang (the LLVMFuzzerTestOneInput wrapper) defaults
# to DWARF5 with clang-19; we force it to DWARF3 via $GO_DEBUG_FLAGS on the CGO
# compile and the final clang++ link, so the FIRST CU carries DWARF3 (< 4 gate).
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
# OSS-Fuzz Go path is ASan-only; UBSan is not part of the Go libFuzzer link. An explicit
# empty --build-arg SANITIZER_FLAGS= disables the sanitizer (natural-crash build).
: "${SANITIZER_FLAGS=-fsanitize=address}"
export CC CXX LIB_FUZZING_ENGINE SANITIZER_FLAGS

: "${GO_DEBUG_FLAGS:=-g -gdwarf-3}"
export CGO_CFLAGS="${CGO_CFLAGS:+$CGO_CFLAGS }$GO_DEBUG_FLAGS"
export CGO_CXXFLAGS="${CGO_CXXFLAGS:+$CGO_CXXFLAGS }$GO_DEBUG_FLAGS"

# Air-gapped contract (SPEC §6.5): the PATCH tier re-runs build.sh OFFLINE. The module
# cache under the pinned $GOMODCACHE doubles as a FILE PROXY; file proxy first, network
# only as a fallback for cache-misses on the first (online) build.
export GOFLAGS="${GOFLAGS:--mod=mod}"
export GOPROXY="${GOPROXY:-file://$(go env GOMODCACHE)/cache/download,https://proxy.golang.org,direct}"
export GOTOOLCHAIN="${GOTOOLCHAIN:-local}"

: "${SRC:=/mayhem}"
cd "$SRC"
go version

mkdir -p "$SRC/mayhem-build"

TARGET="go-org-org-fuzz"
echo "=== building $TARGET (go114-fuzz-build, org.Fuzz) ==="
# go114-fuzz-build wraps org.Fuzz into a libFuzzer archive (builds with the gofuzz tag).
go114-fuzz-build -func Fuzz -o "$SRC/mayhem-build/$TARGET.a" github.com/niklasfasching/go-org/org
# Link the archive into a libFuzzer binary with clang (ASan); DWARF3 on the C-shim CU.
$CXX $SANITIZER_FLAGS $LIB_FUZZING_ENGINE $GO_DEBUG_FLAGS "$SRC/mayhem-build/$TARGET.a" -o "/mayhem/$TARGET"
echo "built /mayhem/$TARGET"

# Pre-warm the test build cache so mayhem/test.sh only RUNS (go test compiles on demand;
# compiling here keeps the offline test.sh run fast and cache-resolved).
go test -count=1 -run xxx_nothing_xxx ./org ./blorg > /dev/null

# Oracle support (SPEC §6.3 anti-reward-hack): pure-Go binaries and the `go` tool are
# statically linked, so LD_PRELOAD bypasses them. test.sh runs the suite through this thin
# dynamically-linked C shim, which IS intercepted by LD_PRELOAD — when sabotaged, the shim
# _exit(0)s before exec(), producing no test output → the oracle counts differ → detected.
cat > "$SRC/mayhem-build/test-runner.c" << 'CEOF'
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#define GOBIN "/opt/toolchains/go/bin/go"
int main(int argc, char **argv) {
    int nfixed = 6; /* go test -json -count=1 pkg1 pkg2 */
    char **args = (char **)malloc((nfixed + argc) * sizeof(char *));
    if (!args) return 1;
    int i = 0;
    args[i++] = (char *)GOBIN;
    args[i++] = (char *)"test";
    args[i++] = (char *)"-json";
    args[i++] = (char *)"-count=1";
    args[i++] = (char *)"github.com/niklasfasching/go-org/org";
    args[i++] = (char *)"github.com/niklasfasching/go-org/blorg";
    for (int j = 1; j < argc; j++) args[i++] = argv[j];
    args[i] = NULL;
    execv(GOBIN, args);
    perror("execv " GOBIN);
    return 127;
}
CEOF
$CC -o "$SRC/mayhem-build/test-runner" "$SRC/mayhem-build/test-runner.c"
echo "built $SRC/mayhem-build/test-runner (go test shim)"

echo "build.sh complete:"
ls -la "/mayhem/$TARGET"
