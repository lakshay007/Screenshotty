#!/bin/zsh
# Builds build/Screenshotty.app. Run `./build.sh install` to also copy it to /Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Screenshotty.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

# Use the SDK that ships with the active toolchain; `xcrun` can pick a newer one the compiler can't read.
SDK="$(xcode-select -p)/SDKs/MacOSX.sdk"
[[ -d "$SDK" ]] || SDK="$(xcrun --show-sdk-path)"

swiftc -O -sdk "$SDK" -target "$(uname -m)-apple-macos14.0" \
    -o "$APP/Contents/MacOS/Screenshotty" Sources/*.swift
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
    pkill -x Screenshotty || true
    rm -rf /Applications/Screenshotty.app
    cp -R "$APP" /Applications/
    open /Applications/Screenshotty.app
    echo "Installed and launched /Applications/Screenshotty.app"
fi
