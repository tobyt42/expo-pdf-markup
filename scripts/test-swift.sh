#!/bin/bash
# Runs Swift XCTests and shows only test results.
# Exit code reflects test pass/fail.

set -o pipefail

xcodebuild test \
  -workspace example/ios/expopdfmarkupexample.xcworkspace \
  -scheme expopdfmarkupexampleTests \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.3.1' \
  -only-testing:expopdfmarkupexampleTests \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO \
  2>&1 | grep -E "^Test |^	|^\*\*"
