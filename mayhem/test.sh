#!/usr/bin/env bash
#
# mayhem/test.sh — RUN this repo's OWN functional test suite (already built by mayhem/build.sh).
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
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

# 1) Upstream's own gtest suites (mayhem/tests.txt), built by build.sh into $SRC/xls_tests with the project's normal
#    flags: the same test sources as the Bazel targets, against the slice of the library the fuzzers use. Suites not
#    run, and why:
#      xls/ir/ir_parser_round_trip_test.cc, xls/ir/value_test.cc - need fuzztest (FUZZ_TEST, IrFuzzDomain), which is
#        not available offline and not part of this slice.
#    Each binary must run at least one test and report a count that matches its OK/FAILED/SKIPPED lines, so a binary
#    that exits 0 without running tests fails; a crash or non-zero exit counts as a failure.
# Run from $SRC: parser_test's ReadStubFile reads xls/dslx/frontend/builtin_stubs.x relative to the source root.
passed=0; failed=0; skipped=0
while read -r t; do
  name=$(basename "$t" .cc)
  bin="$SRC/xls_tests/$name"
  [ -x "$bin" ] || { echo "missing $bin (mayhem/build.sh builds it)" >&2; failed=$((failed + 1)); continue; }
  out=$("$bin" 2>&1); rc=$?
  ran=$(printf '%s\n' "$out" | sed -n 's/^\[==========\] \([0-9][0-9]*\) tests\? from .* ran\..*/\1/p' | tail -1)
  ok=$(printf '%s\n' "$out" | grep -c '^\[       OK \] ')
  bad=$(printf '%s\n' "$out" | grep -c '^\[  FAILED  \] .* (')
  skip=$(printf '%s\n' "$out" | grep -c '^\[  SKIPPED \] .* (')
  if [ -z "$ran" ] || [ "$ran" -eq 0 ] || [ $((ok + bad + skip)) -ne "$ran" ]; then
    echo "FAIL $name: no consistent gtest summary (ran='${ran:-}' ok=$ok failed=$bad skipped=$skip rc=$rc)" >&2
    printf '%s\n' "$out" | tail -20 >&2
    failed=$((failed + 1)); continue
  fi
  if [ "$rc" -ne 0 ] && [ "$bad" -eq 0 ]; then
    echo "FAIL $name: exit status $rc with no failed test" >&2; failed=$((failed + 1))
  fi
  printf '%s\n' "$out" | grep '^\[  FAILED  \] .* (' >&2 || true
  echo "$name: $ok passed, $bad failed, $skip skipped"
  passed=$((passed + ok)); failed=$((failed + bad)); skipped=$((skipped + skip))
done < "$SRC/mayhem/tests.txt"

# 2) Known-answer checks: mayhem/kat/xls_kat.cc (built by build.sh with normal flags into $SRC/xls_kat) parses fixed IR,
# DSLX and number inputs with XLS's own parsers and prints one name=value line per check. Each line is compared with
# the answer the parsers must produce, so a build that exits 0 without parsing (or parses wrongly) fails.
KAT="$SRC/xls_kat"
[ -x "$KAT" ] || { echo "missing $KAT (mayhem/build.sh builds it)" >&2; emit_ctrf "gtest+kat" "$passed" $((failed + 1)) "$skipped"; exit 1; }

EXPECTED='ir_parse=ok
ir_package_name=kat
ir_function_count=1
ir_function_found=ok
ir_function_params=3
ir_function_nodes=5
ir_return_op=add
ir_reject_bad_op=error
value_parse=ok
value_hex=bits[8]:0x12
value_dec=bits[8]:18
tuple_dec=(bits[1]:1, bits[4]:9)
dslx_parse=ok
dslx_module_name=kat
dslx_function_count=2
dslx_has_add=1
dslx_reject_bad=error
dslx_token_count=5
num_hex_bits=13
num_int64=-17
num_uint64=165
num_reject=error
fmt_steps=4
fmt_operands=2'

ACTUAL=$("$KAT" 2>/dev/null)
while IFS= read -r want; do
  key=${want%%=*}
  got=$(printf '%s\n' "$ACTUAL" | grep -m1 "^${key}=" || true)
  if [ "$got" = "$want" ]; then passed=$((passed + 1)); else failed=$((failed + 1)); echo "FAIL $key: want '$want' got '$got'" >&2; fi
done <<< "$EXPECTED"
emit_ctrf "gtest+kat" "$passed" "$failed" "$skipped"
