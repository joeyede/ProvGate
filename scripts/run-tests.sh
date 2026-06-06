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
DESTINATION="platform=iOS Simulator,name=${SIM_NAME}"

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
    # so the in-simulator test process inherits them.
    xcrun simctl bootstatus "$SIM_NAME" -b >/dev/null 2>&1 || xcrun simctl boot "$SIM_NAME" 2>/dev/null || true
    xcrun simctl spawn booted launchctl setenv PROVGATE_TEST_USERNAME "${PROVGATE_TEST_USERNAME:-}"
    xcrun simctl spawn booted launchctl setenv PROVGATE_TEST_PASSWORD "${PROVGATE_TEST_PASSWORD:-}"
fi

xcodebuild test \
    -project ProvGate.xcodeproj \
    -scheme ProvGate \
    -destination "$DESTINATION" \
    -only-testing:ProvGateTests \
    2>&1 | grep -E "✔ Test|✘ Test|✔ Suite|✘ Suite|Test run with|error:" || true
