#!/usr/bin/bash
# Bound a child command before Quickshell collects its stdout.
#
# The long-lived shell used to read `wl-paste` and the settings helper with
# StdioCollector and no producer ceiling. A clipboard owner (or a helper that
# never closes stdout) could hold that read open or feed it without limit.
#
# This supervisor is the producer side of those two streams:
#   paste   API-key clipboard text, 4096 bytes, 2s deadline
#   helper  settings CLI JSON,      262144 bytes, 20s deadline
#
# `head -c (MAX + 1)` stops the child once the ceiling is crossed so overflow
# is rejected rather than silently truncated. `timeout -k` is an absolute
# deadline: SIGTERM, then SIGKILL. `setsid` runs that deadline in its own
# session, so killing the wrapper still leaves a process group that the
# deadline reaps. Caps are constants; the environment cannot raise them.
set -uo pipefail
export LC_ALL=C

mode=${1:-}
shift || true
if [ "${1:-}" != "--" ]; then
  printf '%s\n' "1" "bounded-stdio: expected MODE -- CMD"
  exit 0
fi
shift

case "$mode" in
  paste)
    MAX=4096
    DEADLINE=2
    KILL_AFTER=1
    OVER_MSG="Clipboard text is too long to be an API key"
    TIME_MSG="Clipboard read timed out"
    FAIL_MSG="Clipboard read failed"
    ;;
  helper)
    MAX=262144
    DEADLINE=20
    KILL_AFTER=2
    OVER_MSG="Settings helper output exceeded 262144 bytes"
    TIME_MSG="Settings helper timed out"
    FAIL_MSG="Settings helper failed"
    ;;
  *)
    printf '%s\n' "1" "bounded-stdio: unknown mode"
    exit 0
    ;;
esac

if [ "$#" -eq 0 ]; then
  printf '%s\n' "1" "$FAIL_MSG"
  exit 0
fi

# `${#out}` is a byte count because LC_ALL=C. The extra byte is how overflow
# is detected; it is never forwarded to the shell.
out=$(/usr/bin/setsid -w /usr/bin/timeout -k "$KILL_AFTER" -- "$DEADLINE" "$@" | /usr/bin/head -c $((MAX + 1)))
rc=$?

if [ "${#out}" -gt "$MAX" ]; then
  printf '%s\n' "1" "$OVER_MSG"
  exit 0
fi

# 124: deadline fired. 137: SIGKILL after -k. 143: the child died on SIGTERM.
if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ] || [ "$rc" -eq 143 ]; then
  printf '%s\n' "1" "$TIME_MSG"
  exit 0
fi

if [ "$rc" -ne 0 ]; then
  # wl-paste exits 1 when nothing is selected. That is an empty clipboard,
  # not a hung owner.
  if [ "$mode" = "paste" ] && [ "$rc" -eq 1 ] && [ -z "$out" ]; then
    printf '%s\n' "1" "Clipboard has no text to paste"
    exit 0
  fi
  printf '%s\n' "1" "$FAIL_MSG"
  exit 0
fi

printf '%s\n' "0"
printf '%s' "$out"
exit 0
