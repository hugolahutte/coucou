#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-inbox.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/App/ConversationInbox.swift tests/ConversationInboxTests.swift -o "$TEST_DIR/inbox-tests"
"$TEST_DIR/inbox-tests"
swiftc NotchBuddy/Sources/App/ChatSafety.swift tests/ChatSafetyTests.swift -o "$TEST_DIR/chat-safety-tests"
"$TEST_DIR/chat-safety-tests"
swiftc NotchBuddy/Sources/App/ConversationInbox.swift \
    NotchBuddy/Sources/App/ConversationInboxStore.swift \
    tests/ConversationInboxStoreTests.swift -o "$TEST_DIR/store-tests"
"$TEST_DIR/store-tests"
