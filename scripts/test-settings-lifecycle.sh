#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/settings-lifecycle
xcrun swiftc app/DockVisibilityController.swift app/SettingsWindow.swift tests/settings-lifecycle/main.swift -o build/settings-lifecycle/checks
build/settings-lifecycle/checks
