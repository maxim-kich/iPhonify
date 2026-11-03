#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
xcrun swiftc app/PermissionState.swift tests/permission-state/main.swift -o build/test-permissions
build/test-permissions
