#!/bin/bash
# Compiles bigyap's pure logic sources together with the assertion suite and runs it.
# Usage: ./Tests/run-tests.sh
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="$(mktemp -d)/bigyap-logic-tests"
xcrun swiftc -swift-version 6 \
  bigyap/Services/FuzzyMatcher.swift \
  bigyap/Services/TranscriptProcessor.swift \
  bigyap/Services/TranscriptEditPolicy.swift \
  bigyap/Services/VoiceActivityTrimmer.swift \
  bigyap/Services/PlaybackPausePolicy.swift \
  Tests/main.swift \
  -o "$OUT"
exec "$OUT"
