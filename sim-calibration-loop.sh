#!/usr/bin/env bash
#
# Automated calibration soak test for the Apple Watch simulator.
#
# Builds the Watch app, installs it on the paired Watch sim, launches it with
# CALIBRATION_TEST_LOOPS / CALIBRATION_RATE_SECONDS environment variables, and
# streams the structured os.Logger output. After the soak window, parses the
# log for ring-scale jumps, missed completions (freezes), and rate transitions.
#
# Usage:
#   ./sim-calibration-loop.sh                  # 5 loops, 5s/rate (~3 min)
#   LOOPS=3 RATE_SECONDS=8 ./sim-calibration-loop.sh
#
set -euo pipefail

LOOPS="${LOOPS:-5}"
RATE_SECONDS="${RATE_SECONDS:-5}"

WATCH_UDID="9BD2B535-654B-4604-9AF8-CF28880CB072"   # Apple Watch Series 11 (46mm)
WORKSPACE="Amach Breathe.xcworkspace"
WATCH_SCHEME="AmachBreatheWatch"
WATCH_BUNDLE_ID="com.amach.AmachBreathe.watchkitapp"
WATCH_APP_NAME="Amach Breathe Watch.app"
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData/AmachBreathe-cal-loop"
WATCH_LOG="/tmp/sim-cal-loop-build.log"
RUN_LOG="/tmp/sim-cal-loop-run.log"

# Wall-clock budget per loop. The 6 candidate breath cycles sum to ~64 s
# (60/4.5 + 60/5 + 60/5.5 + 60/6 + 60/6.5 + 60/7); each rate spends its window
# (RATE_SECONDS) plus up to one breath cycle waiting for the next inhale
# boundary, so the realistic floor is `RATE_SECONDS * 6 + 64`. Add the
# runner's ~3.5 s inter-iteration spacing and a 50% margin.
PER_LOOP=$(( (RATE_SECONDS * 6 + 64 + 4) * 3 / 2 ))
BUDGET=$(( LOOPS * PER_LOOP + 60 ))

cd "$(dirname "$0")"

echo "🚀 Booting Watch sim..."
xcrun simctl boot "$WATCH_UDID" 2>/dev/null || true
xcrun simctl bootstatus "$WATCH_UDID" >/dev/null
echo "✅ Booted."

echo "🔨 Building Watch app... (log: $WATCH_LOG)"
if ! xcodebuild \
      -workspace "$WORKSPACE" \
      -scheme "$WATCH_SCHEME" \
      -configuration Debug \
      -destination "platform=watchOS Simulator,id=$WATCH_UDID" \
      -derivedDataPath "$DERIVED_DATA" \
      CODE_SIGNING_ALLOWED=NO \
      build > "$WATCH_LOG" 2>&1; then
  echo "❌ Watch build failed. Last 60 lines:"
  tail -60 "$WATCH_LOG"
  exit 1
fi
echo "✅ Built."

WATCH_APP_PATH="$DERIVED_DATA/Build/Products/Debug-watchsimulator/$WATCH_APP_NAME"
if [[ ! -d "$WATCH_APP_PATH" ]]; then
  echo "❌ Built app not found at: $WATCH_APP_PATH"
  exit 1
fi

echo "📦 Installing..."
xcrun simctl install "$WATCH_UDID" "$WATCH_APP_PATH"

echo "🧹 Terminating any prior instance..."
xcrun simctl terminate "$WATCH_UDID" "$WATCH_BUNDLE_ID" 2>/dev/null || true

echo "🪵 Starting log stream → $RUN_LOG"
# `--level info` is required: os.Logger.info() messages are NOT emitted to the
# unified log by default. Without this flag the stream is silent, which makes
# it look like nothing is happening.
xcrun simctl spawn "$WATCH_UDID" log stream \
  --predicate 'subsystem == "com.amach.AmachBreathe"' \
  --level info \
  --style compact \
  > "$RUN_LOG" 2>&1 &
LOG_PID=$!
trap "kill $LOG_PID 2>/dev/null || true" EXIT

# Brief settle so the stream is up before launch.
sleep 1

echo "▶️  Launching Watch app with CALIBRATION_TEST_LOOPS=$LOOPS CALIBRATION_RATE_SECONDS=$RATE_SECONDS..."
SIMCTL_CHILD_CALIBRATION_TEST_LOOPS="$LOOPS" \
SIMCTL_CHILD_CALIBRATION_RATE_SECONDS="$RATE_SECONDS" \
  xcrun simctl launch "$WATCH_UDID" "$WATCH_BUNDLE_ID" >/dev/null

echo "⏳ Soak window: ${BUDGET}s (LOOPS=$LOOPS, RATE_SECONDS=$RATE_SECONDS)..."
ELAPSED=0
DONE_MARKER="TEST_LOOP_ALL_DONE"
INTERVAL=2
while (( ELAPSED < BUDGET )); do
  if grep -q "$DONE_MARKER" "$RUN_LOG" 2>/dev/null; then
    echo "✅ Soak finished early at ${ELAPSED}s (saw TEST_LOOP_ALL_DONE)."
    break
  fi
  sleep "$INTERVAL"
  ELAPSED=$(( ELAPSED + INTERVAL ))
done
if (( ELAPSED >= BUDGET )); then
  echo "⏱  Hit BUDGET=${BUDGET}s without TEST_LOOP_ALL_DONE — proceeding to summarize."
fi

# Stop the stream so the file is fully flushed.
kill $LOG_PID 2>/dev/null || true
wait $LOG_PID 2>/dev/null || true
trap - EXIT

echo
echo "──── Calibration Loop Report ────"

# Filter our subsystem lines into a tidy file.
CAL_LINES=$(grep -E "TEST_LOOP|RATE_START|RATE_DONE|RATE_WINDOW_EXPIRED|INHALE_BOUNDARY|RING_JUMP|CALIBRATION_COMPLETE|CALIBRATION_FAILED" "$RUN_LOG" || true)

if [[ -z "$CAL_LINES" ]]; then
  echo "(no Calibration / CalibrationTest log lines captured — check $RUN_LOG)"
  exit 1
fi

LOOP_STARTS=$(echo "$CAL_LINES" | grep -c "TEST_LOOP_START" || true)
LOOP_COMPLETES=$(echo "$CAL_LINES" | grep -c "TEST_LOOP_COMPLETE" || true)
LOOP_FAILS=$(echo "$CAL_LINES" | grep -c "TEST_LOOP_FAILED" || true)
LOOP_FREEZES=$(echo "$CAL_LINES" | grep -c "TEST_LOOP_FREEZE" || true)
RING_JUMPS=$(echo "$CAL_LINES" | grep -c "RING_JUMP" || true)
RATE_TRANSITIONS=$(echo "$CAL_LINES" | grep -c "INHALE_BOUNDARY" || true)
COMPLETIONS=$(echo "$CAL_LINES" | grep -c "CALIBRATION_COMPLETE" || true)
FAILURES=$(echo "$CAL_LINES" | grep -c "CALIBRATION_FAILED" || true)

printf "Loops requested      : %s\n" "$LOOPS"
printf "TEST_LOOP_START      : %s\n" "$LOOP_STARTS"
printf "TEST_LOOP_COMPLETE   : %s\n" "$LOOP_COMPLETES"
printf "TEST_LOOP_FAILED     : %s\n" "$LOOP_FAILS"
printf "TEST_LOOP_FREEZE     : %s  ← any non-zero is a hang\n" "$LOOP_FREEZES"
printf "CALIBRATION_COMPLETE : %s\n" "$COMPLETIONS"
printf "CALIBRATION_FAILED   : %s\n" "$FAILURES"
printf "Inhale boundaries    : %s\n" "$RATE_TRANSITIONS"
printf "RING_JUMP events     : %s  ← non-zero = ring scale discontinuity\n" "$RING_JUMPS"

if (( RING_JUMPS > 0 )); then
  echo
  echo "── ring-scale discontinuities ──"
  echo "$CAL_LINES" | grep "RING_JUMP" | head -20
fi

if (( LOOP_FREEZES > 0 )); then
  echo
  echo "── freezes detected ──"
  echo "$CAL_LINES" | grep "TEST_LOOP_FREEZE"
fi

echo
echo "Full log: $RUN_LOG"
echo "Filtered cal events: $(grep -c -E "TEST_LOOP|RATE_START|RATE_DONE|RING_JUMP|CALIBRATION_" "$RUN_LOG" || true) lines"
