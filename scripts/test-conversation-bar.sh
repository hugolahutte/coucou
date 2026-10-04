#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
BAR_TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-bar-tests.XXXXXX")"
trap 'rm -rf "$BAR_TEST_DIR"' EXIT
swiftc -swift-version 6 -module-cache-path "$BAR_TEST_DIR/cache" \
  NotchBuddy/Sources/App/IslandStateMachine.swift tests/ConversationBarStateTests.swift \
  -o "$BAR_TEST_DIR/tests"
"$BAR_TEST_DIR/tests"
