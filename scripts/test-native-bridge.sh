#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
FLAGS=(-std=c11 -O1 -g -pthread -I src/TouchBridge/include)
if [[ "${IPHONIFY_SANITIZE_THREADS:-0}" = 1 ]]; then FLAGS+=(-fsanitize=thread); fi
xcrun clang "${FLAGS[@]}" tests/native-bridge/main.c -o build/test-native-bridge
build/test-native-bridge
echo 'Native bridge: concurrent delivery/stop dispatcher passed without opening a trackpad device'
