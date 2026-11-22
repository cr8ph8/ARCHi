#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERIFY=0
REVIEW=0
INSTALL=0
LAUNCH=1
STAGE_ONLY=0
MEMORY_DEMO=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --memory-demo) MEMORY_DEMO=1; STAGE_ONLY=1; LAUNCH=0 ;;
        --verify) VERIFY=1 ;;
        --review) REVIEW=1 ;;
        --install) INSTALL=1 ;;
        --build-only) LAUNCH=0 ;;
        --stage-only) STAGE_ONLY=1; LAUNCH=0 ;;
        *) echo "Usage: $0 [--verify] [--review] [--install] [--build-only] [--stage-only] [--memory-demo]" >&2; exit 2 ;;
    esac
    shift
done
APP_NAME="ARCHi Desktop Preview"
APP_IDENTIFIER="com.quotient.archi.desktop.preview"
APP_DIR="/private/tmp/archi-desktop-preview-${UID}/$APP_NAME.app"
PREVIOUS_EXECUTABLE="$REPO_ROOT/output/native/ARCHi Desktop Preview.app/Contents/MacOS/ARCHiDesktop"
if [[ "$REVIEW" == 1 ]]; then
    # A separate bundle lets development QA leave the user's open session intact.
    APP_NAME="ARCHi Development Review"
    APP_IDENTIFIER="com.quotient.archi.desktop.review"
    APP_DIR="/private/tmp/archi-desktop-review-${UID}/$APP_NAME.app"
    PREVIOUS_EXECUTABLE=""
fi
if [[ "$MEMORY_DEMO" == 1 ]]; then
    if [[ "$INSTALL" == 1 || "$REVIEW" == 1 ]]; then exit 2; fi
    APP_NAME="ARCHi Memory Demo"
    APP_IDENTIFIER="com.quotient.archi.desktop.memory-demo"
    PREVIOUS_EXECUTABLE=""
fi
TEMP_APP_EXECUTABLE="$APP_DIR/Contents/MacOS/ARCHiDesktop"
INSTALLED_APP_EXECUTABLE="/Applications/$APP_NAME.app/Contents/MacOS/ARCHiDesktop"
if [[ "$INSTALL" == 1 ]]; then
    # A real bundle survives temporary-directory cleanup and is discoverable
    # through Finder, Spotlight and the Dock. Profiles retain their bundle IDs.
    APP_DIR="/Applications/$APP_NAME.app"
fi
if [[ "$STAGE_ONLY" == 1 ]]; then
    # Use a local staging directory outside synced Documents; Finder metadata
    # can be reattached there during signature verification.
    APP_DIR="/private/tmp/archi-desktop-candidate-${UID}/$APP_NAME.app"
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
        if [[ "$process_command" == "$APP_EXECUTABLE" || ( "$STAGE_ONLY" == 0 && (
              "$process_command" == "$TEMP_APP_EXECUTABLE" ||
              "$process_command" == "$INSTALLED_APP_EXECUTABLE" ||
              ( -n "$PREVIOUS_EXECUTABLE" && "$process_command" == "$PREVIOUS_EXECUTABLE" ) ) ) ]]; then
            echo "$APP_NAME is still running. This build will not replace its open session." >&2
            echo "Export any working draft, save the choices you want to keep, then choose Quit in $APP_NAME. Wait for it to close and rerun this command." >&2
            return 1
        fi
    done <<< "$process_ids"
}

# Preserve the selected profile's owned requests and unsaved work. The user
# quits through the app so its normal Habitat, model and Reactor cleanup runs.
require_selected_app_stopped

# Desktop-only development: retained game source is neither rebuilt nor bundled.
# Re-enabling play is a separate product decision, not a launch dependency.
PLAY_STAGE="$(mktemp -d /private/tmp/archi-desktop-bundle.XXXXXX)"
BUNDLE_DIR="$PLAY_STAGE/$APP_NAME.app"
INSTALL_STAGE=""
trap 'rm -rf "$PLAY_STAGE"; if [[ -n "$INSTALL_STAGE" ]]; then rm -rf "$INSTALL_STAGE"; fi' EXIT

swift build --package-path "$REPO_ROOT/desktop"
if [[ "$VERIFY" == 1 ]]; then swift test --package-path "$REPO_ROOT/desktop"; fi
BIN_DIR="$(swift build --package-path "$REPO_ROOT/desktop" --show-bin-path)"
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
<key>CFBundleShortVersionString</key><string>0.7.0</string>
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
if [[ -e "$APP_DIR" || -L "$APP_DIR" ]]; then
    PREVIOUS_BUNDLE="$APP_DIR.previous.$(date +%Y%m%d-%H%M%S).$$"
    mv "$APP_DIR" "$PREVIOUS_BUNDLE"
fi
if ! mv "$INSTALL_STAGE/$APP_NAME.app" "$APP_DIR"; then
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
