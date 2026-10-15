#!/usr/bin/env bash
# Builds build/windows/Driver.exe and build/Driver-Setup.exe.
# Needs Godot 4.7.2 (GODOT env var or on PATH) with Windows export templates, and NSIS (makensis).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
VERSION="$(grep -oP 'config/version="\K[^"]+' project.godot)"
mkdir -p build/windows
"$GODOT" --headless --import >/dev/null 2>&1 || true
"$GODOT" --headless --export-release "Windows" build/windows/Driver.exe
(cd installer && makensis -V2 -DVERSION="$VERSION" driver.nsi)
ls -lh build/windows/Driver.exe build/Driver-Setup.exe
