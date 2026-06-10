#!/usr/bin/env bash
# Run the full ProvGateTests suite (unit + integration).
#
# Usage:
#   bash scripts/run-tests.sh              # unit tests only; integration suites auto-skip
#   bash scripts/run-tests.sh --with-env   # also run integration suites against the live broker
#
# Integration credentials:
#   The integration suites read PROVGATE_TEST_USERNAME / PROVGATE_TEST_PASSWORD from the
#   *simulator's* launchd environment. iOS Simulator test processes do NOT inherit the
#   parent shell's env, and a scheme <EnvironmentVariable> with value "$(VAR)" is injected
#   LITERALLY (the macro never expands) — which silently feeds garbage credentials to the
#   broker. The only reliable channel is `simctl spawn booted launchctl setenv`, done below.
#
# Credentials live in ~/.provgate-test-env (git-ignored) and are never committed.

set -euo pipefail

SIM_NAME="${SIMULATOR_NAME:-iPhone 17}"
# Prefer UDID when provided by CI (avoids ambiguity when multiple simulators
# share the same name across iOS versions).
if [ -n "${SIMULATOR_UDID:-}" ]; then
    DESTINATION="platform=iOS Simulator,id=${SIMULATOR_UDID}"
else
    DESTINATION="platform=iOS Simulator,name=${SIM_NAME}"
fi

if [[ "${1:-}" == "--with-env" ]]; then
    # The gate-emulator subscribes to gate/test/control and ACKs back on the response
    # topic. If it's running, integration tests that expect NO reply (e.g.
    # timeoutThrowsWhenNoResponseArrives) get an answer and fail. Refuse to run.
    if pgrep -f 'gate-emulator' >/dev/null 2>&1; then
        echo "error: gate-emulator is running (PID $(pgrep -f 'gate-emulator' | tr '\n' ' ')) — it replies on dry-run topics and breaks integration tests." >&2
        echo "       Stop it first:  pkill -f gate-emulator" >&2
        exit 1
    fi

    # shellcheck source=/dev/null
    source ~/.provgate-test-env
    # Ensure the simulator is booted, then push credentials into its launchd environment
    # so the in-simulator test process inherits them. Prefer the UDID (CI) over name.
    SIM_REF="${SIMULATOR_UDID:-$SIM_NAME}"
    xcrun simctl bootstatus "$SIM_REF" -b >/dev/null 2>&1 || xcrun simctl boot "$SIM_REF" 2>/dev/null || true
    xcrun simctl spawn booted launchctl setenv PROVGATE_TEST_USERNAME "${PROVGATE_TEST_USERNAME:-}"
    xcrun simctl spawn booted launchctl setenv PROVGATE_TEST_PASSWORD "${PROVGATE_TEST_PASSWORD:-}"
fi

# Run xcodebuild, stream filtered progress, and propagate xcodebuild's exit code.
# Full output is saved to a temp log; on failure the last 150 lines are printed so
# assertion messages and stack traces are visible in CI without wading through the
# full build log on a pass.
LOG=$(mktemp /tmp/xcodebuild-XXXXXX.log)
trap 'rm -f "$LOG"' EXIT

set +e
xcodebuild test \
    -project ProvGate.xcodeproj \
    -scheme ProvGate \
    -destination "$DESTINATION" \
    -only-testing:ProvGateTests \
    ${RESULT_BUNDLE_PATH:+-resultBundlePath "$RESULT_BUNDLE_PATH"} \
    2>&1 | tee "$LOG" | grep --line-buffered -E \
        "✔ Test|✘ Test|✔ Suite|✘ Suite|Test run with|\*\* TEST|SwiftDriverJobDiscovery|Resolve Package Graph|Resolved source packages|Prepare packages|note: Building|error:"
XCODE_STATUS="${PIPESTATUS[0]}"
set -e

if [ "$XCODE_STATUS" -ne 0 ]; then
    echo ""
    echo "=== xcodebuild output (last 150 lines) ==="
    tail -150 "$LOG"
fi

[ "$XCODE_STATUS" -eq 0 ]
