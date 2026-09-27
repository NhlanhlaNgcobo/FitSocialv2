#!/usr/bin/env bash
# Runs one shot file and prints only the test outcome and the first lines of
# each exception.
#   run.sh <file> [max lines] [test name filter]
cd "$(dirname "$0")/../.."
args=("tool/marketing_shots/$1_test.dart")
[ -n "$3" ] && args+=(--plain-name "$3")
timeout 1800 flutter test "${args[@]}" 2>&1 \
  | sed -n '/: loading /,$p' \
  | grep -E -A4 "was thrown|error:|Error:|\+[0-9]+.*:" \
  | grep -v -E "^\s*$|^--$|elided|asynchronous suspension" | head -${2:-30}
