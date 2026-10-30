#!/bin/bash
# Override IOS_TEST_DESTINATION with an xcodebuild destination to select a device.
set -euo pipefail
cd "$(dirname "$0")/.."

destination="${IOS_TEST_DESTINATION:-}"
if [[ -z "$destination" ]]; then
  devices=$(xcrun simctl list devices available --json)
  device_id=$(node -e '
    const { devices } = JSON.parse(process.argv[1]);
    const candidates = Object.entries(devices)
      .filter(([runtime]) => runtime.includes(".iOS-"))
      .sort(([a], [b]) => b.localeCompare(a, undefined, { numeric: true }))
      .flatMap(([, devices]) => devices)
      .filter(device => device.isAvailable && device.name.startsWith("iPhone"));
    if (!candidates.length) {
      console.error("No available iPhone simulator; install an iOS runtime or set IOS_TEST_DESTINATION.");
      process.exit(1);
    }
    console.log((candidates.find(device => device.state === "Booted") || candidates[0]).udid);
  ' "$devices")
  destination="platform=iOS Simulator,id=$device_id"
fi

mkdir -p build/test-results
xcodebuild test \
  -workspace example/ios/expopdfmarkupexample.xcworkspace \
  -scheme expopdfmarkupexampleTests \
  -configuration Debug \
  -destination "$destination" \
  -destination-timeout 120 \
  -resultBundlePath "build/test-results/ios-$(date +%s).xcresult" \
  -only-testing:expopdfmarkupexampleTests \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  2>&1 | tee build/test-results/ios.log
