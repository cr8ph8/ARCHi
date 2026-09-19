#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Keep generated build products outside file-provider managed Documents.
BUILD_SCRATCH="${ARCHI_BUILD_SCRATCH_PATH:-/private/tmp/archi-desktop-build-${UID}}"
VERIFY=0
LAUNCH=1
STAGE_ONLY=0
STAGE_DIR=""
UNITY_PLAYER=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --verify) VERIFY=1 ;;
        # Compatibility aliases: both now target the one installed ARCHi app.
        --review|--install) : ;;
        --build-only) LAUNCH=0 ;;
        --stage-only) STAGE_ONLY=1; LAUNCH=0 ;;
        --stage-dir)
            [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || { echo "--stage-dir requires a new absolute directory path." >&2; exit 2; }
            shift; STAGE_DIR="$1" ;;
        --unity-player) shift; UNITY_PLAYER="${1:?--unity-player requires an app bundle path}" ;;
        *) echo "Usage: $0 [--verify] [--review] [--install] [--build-only] [--stage-only [--stage-dir NEW_ABSOLUTE_DIR]] [--unity-player APP]" >&2; exit 2 ;;
    esac
    shift
done
APP_NAME="ARCHi"
# Retain the identifier/profile that owns the existing KIN. Renaming the
# product must not silently create an empty identity or migrate authored saves.
APP_IDENTIFIER="com.quotient.archi.desktop.review"
APP_DIR="/Applications/$APP_NAME.app"
if [[ -n "$STAGE_DIR" ]]; then
    [[ "$STAGE_ONLY" == 1 && "$STAGE_DIR" == /* ]] || { echo "--stage-dir requires --stage-only and a new absolute directory path." >&2; exit 2; }
    [[ ! -e "$STAGE_DIR" && ! -L "$STAGE_DIR" ]] || { echo "Staging directory already exists; choose a new path. Nothing was replaced." >&2; exit 2; }
    STAGE_PARENT="$(cd "$(dirname "$STAGE_DIR")" && pwd -P)" || { echo "The staging parent directory must already exist." >&2; exit 2; }
    STAGE_DIR="$STAGE_PARENT/$(basename "$STAGE_DIR")"
    case "$STAGE_DIR" in
        /Applications|/Applications/*|*/Applications|*/Applications/*|*.[aA][pP][pP]|*.[aA][pP][pP]/*)
            echo "Use a staging directory outside Applications and existing app bundles." >&2; exit 2 ;;
    esac
    # Reserve the task's directory atomically. A concurrent invocation with
    # the same destination must fail before building or touching app files.
    mkdir -m 700 "$STAGE_DIR" || { echo "Could not reserve a new staging directory. Nothing was replaced." >&2; exit 2; }
fi
if [[ "$STAGE_ONLY" == 1 ]]; then
    # Use a local staging directory outside synced Documents; Finder metadata
    # can be reattached there during signature verification.
    APP_DIR="${STAGE_DIR:-/private/tmp/archi-desktop-candidate-${UID}}/$APP_NAME.app"
fi
APP_EXECUTABLE="$APP_DIR/Contents/MacOS/ARCHiDesktop"

require_selected_app_stopped() {
    local process_id process_command process_ids query_status
    if process_ids="$(pgrep -x ARCHiDesktop)"; then
        :
    else
        query_status=$?
        if [[ "$query_status" != 1 ]]; then
            echo "Could not check whether $APP_NAME is running. No app files were replaced; quit the selected app and retry with process inspection available." >&2
            return 1
        fi
    fi
    while IFS= read -r process_id; do
        [[ -n "$process_id" ]] || continue
        process_command="$(ps -p "$process_id" -o comm= 2>/dev/null || true)"
        if [[ "$process_command" == "$APP_EXECUTABLE" || ( "$STAGE_ONLY" == 0 && -n "$process_command" ) ]]; then
            echo "ARCHi is still running: $process_command" >&2
            echo "This build will not replace or create another personal app while ARCHi, Development Review or Desktop Preview has an open session." >&2
            echo "Export any working draft, save the choices you want to keep, then choose Quit in the open app. Wait for it to close and rerun this command. Use --stage-only to prepare a candidate without installing or launching." >&2
            return 1
        fi
    done <<< "$process_ids"
}

# Preserve the selected profile's owned requests and unsaved work. The user
# quits through the app so its normal Habitat, model and Reactor cleanup runs.
require_selected_app_stopped

# Keep the existing qualified Unity helper when updating the native app. A
# missing argument must never silently strip Companion & Arena from ARCHi.
if [[ -z "$UNITY_PLAYER" ]]; then
    if [[ "$STAGE_ONLY" == 1 && -d "$APP_DIR/Contents/Resources/UnityCompanion.app" ]]; then
        UNITY_PLAYER="$APP_DIR/Contents/Resources/UnityCompanion.app"
    elif [[ -d "/Applications/ARCHi.app/Contents/Resources/UnityCompanion.app" ]]; then
        UNITY_PLAYER="/Applications/ARCHi.app/Contents/Resources/UnityCompanion.app"
    else
        echo "ARCHi requires its Unity Companion & Arena player. Pass --unity-player /path/to/qualified-player.app for the first build. No app was replaced." >&2
        exit 2
    fi
fi

# The native app owns the session. The retained browser game is not a build
# dependency; Unity is copied into this app as its internal rendering helper.
PLAY_STAGE="$(mktemp -d /private/tmp/archi-desktop-bundle.XXXXXX)"
BUNDLE_DIR="$PLAY_STAGE/$APP_NAME.app"
INSTALL_STAGE=""
trap 'rm -rf "$PLAY_STAGE"; if [[ -n "$INSTALL_STAGE" ]]; then rm -rf "$INSTALL_STAGE"; fi' EXIT

swift build --package-path "$REPO_ROOT/desktop" --scratch-path "$BUILD_SCRATCH"
if [[ "$VERIFY" == 1 ]]; then swift test --package-path "$REPO_ROOT/desktop" --scratch-path "$BUILD_SCRATCH"; fi
BIN_DIR="$(swift build --package-path "$REPO_ROOT/desktop" --scratch-path "$BUILD_SCRATCH" --show-bin-path)"
mkdir -p "$BUNDLE_DIR/Contents/MacOS" "$BUNDLE_DIR/Contents/Resources"
# Building can take time. Recheck in case this profile was opened meanwhile,
# immediately before replacing its executable or generated resources.
require_selected_app_stopped
cp "$BIN_DIR/ARCHiDesktop" "$BUNDLE_DIR/Contents/MacOS/ARCHiDesktop"
# The native art loader uses this packaged location, never a development fallback.
cp -R "$REPO_ROOT/desktop/Sources/ARCHiDesktop/Resources/CompanionArt" "$BUNDLE_DIR/Contents/Resources/CompanionArt"
test -f "$BUNDLE_DIR/Contents/Resources/CompanionArt/archi-pearl-study-v1.png"
cp -R "$REPO_ROOT/desktop/Sources/ARCHiDesktop/Resources/Branding" "$BUNDLE_DIR/Contents/Resources/Branding"
cp "$BUNDLE_DIR/Contents/Resources/Branding/AppIcon.icns" "$BUNDLE_DIR/Contents/Resources/AppIcon.icns"
mkdir -p "$BUNDLE_DIR/Contents/Resources/ReactorBridge"
cp "$REPO_ROOT/desktop/Sources/ARCHiDesktop/Resources/ReactorBridge/worker.py" "$BUNDLE_DIR/Contents/Resources/ReactorBridge/worker.py"
mkdir -p "$BUNDLE_DIR/Contents/Resources/ARC3Bridge"
cp "$REPO_ROOT/desktop/Sources/ARCHiDesktop/Resources/ARC3Bridge/archi_arc3_bridge.py" "$BUNDLE_DIR/Contents/Resources/ARC3Bridge/archi_arc3_bridge.py"
test -s "$BUNDLE_DIR/Contents/Resources/ARC3Bridge/archi_arc3_bridge.py"
if [[ -n "$UNITY_PLAYER" ]]; then
    [[ -d "$UNITY_PLAYER" && "$UNITY_PLAYER" == *.app ]] || { echo "Unity player must be an existing app bundle." >&2; exit 2; }
    # The qualified player may be exposed through an output symlink. Resolve
    # that entry before copying so adapting the helper never edits its source.
    UNITY_PLAYER="$(cd "$UNITY_PLAYER" && pwd -P)"
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$UNITY_PLAYER/Contents/Info.plist")" == "local.archi.unityport" ]] || exit 2
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :ARCHiNativePresentationProtocol' "$UNITY_PLAYER/Contents/Info.plist")" == "1" ]] || exit 2
    codesign --verify --deep --strict "$UNITY_PLAYER"
    cp -R "$UNITY_PLAYER" "$BUNDLE_DIR/Contents/Resources/UnityCompanion.app"
    # Unity owns a rendering window inside ARCHi's session, not a second Dock
    # product. Only adapt and re-sign this generated copy; preserve the source.
    plutil -replace LSUIElement -bool YES "$BUNDLE_DIR/Contents/Resources/UnityCompanion.app/Contents/Info.plist"
    codesign --force --sign - --preserve-metadata=identifier,entitlements,flags "$BUNDLE_DIR/Contents/Resources/UnityCompanion.app"
    codesign --verify --deep --strict "$BUNDLE_DIR/Contents/Resources/UnityCompanion.app"
fi
# A native button has the app's filesystem access, not Codex's Documents access.
# Copy the already-installed runtime into this generated app so Python startup
# never waits on a repository-local pyvenv.cfg or site-packages privacy prompt.
REACTOR_SOURCE_RUNTIME="$REPO_ROOT/output/creative-tools/reactor/runtime"
REACTOR_APP_RUNTIME="$APP_DIR/Contents/Resources/ReactorRuntime"
if [[ -x "$REACTOR_SOURCE_RUNTIME/bin/python3" ]]; then
    # Copy interpreter launchers by value: signed app bundles cannot contain
    # symlinks escaping to the external Python framework.
    cp -RL "$REACTOR_SOURCE_RUNTIME" "$BUNDLE_DIR/Contents/Resources/ReactorRuntime"
fi
cat > "$BUNDLE_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleExecutable</key><string>ARCHiDesktop</string>
<key>CFBundleIdentifier</key><string>$APP_IDENTIFIER</string>
<key>CFBundleName</key><string>$APP_NAME</string>
<key>CFBundleDisplayName</key><string>$APP_NAME</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSMicrophoneUsageDescription</key><string>ARCHi uses the microphone only when you click Dictate, to prepare text you review before sending. Audio is not saved.</string>
<key>NSSpeechRecognitionUsageDescription</key><string>ARCHi uses available on-device speech recognition to prepare a draft. No online speech fallback is used, and nothing is sent until you choose Send.</string>
<key>ARCHiReactorPython</key><string>$REACTOR_APP_RUNTIME/bin/python3</string>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
PLIST
plutil -lint "$BUNDLE_DIR/Contents/Info.plist"
# Finder may attach metadata after a preview is opened; remove it only from this
# regenerated development bundle before signing the next build.
xattr -cr "$BUNDLE_DIR"
codesign --force --sign - "$BUNDLE_DIR"
codesign --verify --deep --strict "$BUNDLE_DIR"
# Only promote a complete signed bundle. Keep the previous installation as a
# recoverable sibling; application-support data is never copied or replaced.
require_selected_app_stopped
mkdir -p "$(dirname "$APP_DIR")"
# Copy and verify before touching the previous bundle. The two final renames
# then stay on the destination filesystem, including on a separate volume.
INSTALL_STAGE="$(mktemp -d "$(dirname "$APP_DIR")/.archi-install.XXXXXX")"
cp -R "$BUNDLE_DIR" "$INSTALL_STAGE/$APP_NAME.app"
# Finder/iCloud can attach metadata while a generated bundle is copied into
# Documents. Clear it on this new staging copy before verifying its signature.
xattr -cr "$INSTALL_STAGE/$APP_NAME.app"
codesign --verify --deep --strict "$INSTALL_STAGE/$APP_NAME.app"
require_selected_app_stopped
PREVIOUS_BUNDLE=""
if [[ -n "$STAGE_DIR" && ( -e "$APP_DIR" || -L "$APP_DIR" ) ]]; then
    echo "The reserved staging destination now contains an app. Nothing was replaced; choose a new --stage-dir." >&2
    exit 1
fi
if [[ -z "$STAGE_DIR" && ( -e "$APP_DIR" || -L "$APP_DIR" ) ]]; then
    PREVIOUS_BUNDLE="$APP_DIR.previous.$(date +%Y%m%d-%H%M%S).$$"
    mv "$APP_DIR" "$PREVIOUS_BUNDLE"
fi
if [[ -n "$STAGE_DIR" ]]; then
    # Do not displace a bundle that appeared after the final check. Moving
    # into the parent keeps an existing same-name entry protected by -n.
    mv -n "$INSTALL_STAGE/$APP_NAME.app" "$STAGE_DIR/"
    if [[ -e "$INSTALL_STAGE/$APP_NAME.app" ]]; then
        echo "Staging destination was occupied during promotion. Its bundle was preserved." >&2
        exit 1
    fi
elif ! mv "$INSTALL_STAGE/$APP_NAME.app" "$APP_DIR"; then
    if [[ -n "$PREVIOUS_BUNDLE" && ! -e "$APP_DIR" && ! -L "$APP_DIR" ]]; then
        mv "$PREVIOUS_BUNDLE" "$APP_DIR"
        echo "Could not install $APP_NAME; the previous bundle was restored." >&2
    else
        echo "Could not install $APP_NAME. Any previous bundle remains at: ${PREVIOUS_BUNDLE:-none (first install)}" >&2
    fi
    exit 1
fi
if [[ "$LAUNCH" == 1 ]]; then
    open "$APP_DIR"
    echo "Built and requested launch: $APP_DIR"
else
    echo "Built without launch: $APP_DIR"
fi
if [[ -n "$PREVIOUS_BUNDLE" ]]; then echo "Previous bundle preserved: $PREVIOUS_BUNDLE"; fi
