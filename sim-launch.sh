#!/usr/bin/env bash
set -euo pipefail

# Paired simulators
IPHONE_UDID="660C2285-6AF9-4C1F-8A9B-F6D98F1CEEC3"   # iPhone 17 Pro Max
WATCH_UDID="9BD2B535-654B-4604-9AF8-CF28880CB072"    # Apple Watch Series 11 (46mm)

# Project bits
WORKSPACE="Amach Breathe.xcworkspace"
IOS_SCHEME="AmachBreathe"
WATCH_SCHEME="AmachBreatheWatch"
IOS_BUNDLE_ID="com.amach.AmachBreathe"
WATCH_BUNDLE_ID="com.amach.AmachBreathe.watchkitapp"
IOS_APP_NAME="Amach Breathe.app"
WATCH_APP_NAME="Amach Breathe Watch.app"

DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData/AmachBreathe-sim-launch"
IOS_LOG="/tmp/sim-launch-ios-build.log"
WATCH_LOG="/tmp/sim-launch-watch-build.log"

cd "$(dirname "$0")"

run_build() {
  local label="$1" scheme="$2" destination="$3" log="$4"
  echo "🔨 Building $label app... (log: $log)"
  if ! xcodebuild \
        -workspace "$WORKSPACE" \
        -scheme "$scheme" \
        -configuration Debug \
        -destination "$destination" \
        -derivedDataPath "$DERIVED_DATA" \
        CODE_SIGNING_ALLOWED=NO \
        build > "$log" 2>&1; then
    echo "❌ $label build failed. Last 60 lines of log:"
    tail -60 "$log"
    exit 1
  fi
  echo "✅ $label build succeeded."
}

echo "🚀 Booting paired simulators..."
xcrun simctl boot "$IPHONE_UDID" 2>/dev/null || true
xcrun simctl boot "$WATCH_UDID"  2>/dev/null || true

echo "⏳ Waiting for iPhone to finish booting..."
xcrun simctl bootstatus "$IPHONE_UDID" >/dev/null
echo "⏳ Waiting for Watch to finish booting..."
xcrun simctl bootstatus "$WATCH_UDID" >/dev/null
echo "✅ Simulators booted."

run_build "iOS"   "$IOS_SCHEME"   "platform=iOS Simulator,id=$IPHONE_UDID"        "$IOS_LOG"
run_build "Watch" "$WATCH_SCHEME" "platform=watchOS Simulator,id=$WATCH_UDID"     "$WATCH_LOG"

IOS_APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/$IOS_APP_NAME"
WATCH_APP_PATH="$DERIVED_DATA/Build/Products/Debug-watchsimulator/$WATCH_APP_NAME"

if [[ ! -d "$IOS_APP_PATH" ]]; then
  echo "❌ Could not find built iOS app at: $IOS_APP_PATH"
  exit 1
fi
if [[ ! -d "$WATCH_APP_PATH" ]]; then
  echo "❌ Could not find built Watch app at: $WATCH_APP_PATH"
  exit 1
fi

echo "📦 Installing iOS app on iPhone simulator..."
xcrun simctl install "$IPHONE_UDID" "$IOS_APP_PATH"
echo "📦 Installing Watch app on Watch simulator..."
xcrun simctl install "$WATCH_UDID" "$WATCH_APP_PATH"

echo "▶️  Launching iOS app..."
xcrun simctl launch "$IPHONE_UDID" "$IOS_BUNDLE_ID" >/dev/null
echo "▶️  Launching Watch app..."
xcrun simctl launch "$WATCH_UDID" "$WATCH_BUNDLE_ID" >/dev/null

echo "🪟 Bringing Simulator.app to the foreground..."
open -a Simulator

echo ""
echo "🎉 Done! Check your Simulator windows."
