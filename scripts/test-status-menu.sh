#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
xcrun swiftc app/StatusMenu.swift tests/status-menu/main.swift -o build/test-status-menu
build/test-status-menu
