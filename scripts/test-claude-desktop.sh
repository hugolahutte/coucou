#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-claude-desktop.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -module-cache-path "$TEST_DIR/module-cache" NotchBuddy/Sources/App/ConversationInbox.swift \
    NotchBuddy/Sources/App/ClaudeDesktopCapture.swift tests/ClaudeDesktopCaptureTests.swift \
    -o "$TEST_DIR/desktop-tests"
"$TEST_DIR/desktop-tests"
