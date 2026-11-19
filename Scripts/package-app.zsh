#!/bin/zsh
set -euo pipefail

if (( $# > 1 )); then
    print -u2 'Usage: package-app.zsh [output.zip]'
    exit 2
fi

project_dir=${0:A:h:h}
output_zip=${1:-"$project_dir/dist/AsteraDMXMidiBridge.zip"}
output_zip=${output_zip:a}
build_number=${AX1_BUILD_NUMBER:-16}
build_date=$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')

if [[ $output_zip != *.zip || $build_number != <1-> ]]; then
    print -u2 'Use a .zip output path and a positive integer for AX1_BUILD_NUMBER.'
    exit 2
fi

cd "$project_dir"
build_root="$project_dir/.build-packaging"
export CLANG_MODULE_CACHE_PATH="$build_root/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$build_root/module-cache"
typeset -a swift_flags
swift_flags=(
    --scratch-path "$build_root/build"
    --cache-path "$build_root/cache"
    --config-path "$build_root/config"
    --security-path "$build_root/security"
)
if [[ ${AX1_SWIFTPM_NO_SANDBOX:-0} == 1 ]]; then
    swift_flags+=(--disable-sandbox -debug-info-format none)
fi
swift build "${swift_flags[@]}" -c release --product AsteraDMXMidiBridge
bin_dir=$(swift build "${swift_flags[@]}" -c release --show-bin-path)

output_dir=${output_zip:h}
/bin/mkdir -p "$output_dir"
stage_dir=$(/usr/bin/mktemp -d "$output_dir/.ax1bridge.XXXXXXXX")
trap '/bin/rm -rf -- "$stage_dir"' EXIT
app="$stage_dir/AsteraDMXMidiBridge.app"
/bin/mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
/usr/bin/install -m 755 "$bin_dir/AsteraDMXMidiBridge" "$app/Contents/MacOS/AsteraDMXMidiBridge"

plist="$app/Contents/Info.plist"
/bin/cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>AsteraDMXMidiBridge</string>
    <key>CFBundleExecutable</key>
    <string>AsteraDMXMidiBridge</string>
    <key>CFBundleIdentifier</key>
    <string>com.jonpike.ax1bridge</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>AsteraDMXMidiBridge</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.14.0</string>
    <key>CFBundleVersion</key>
    <string>$build_number</string>
    <key>AX1BuildDate</key>
    <string>$build_date</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>AsteraDMXMidiBridge uses your local network to send Art-Net lighting data to your DMX interface.</string>
</dict>
</plist>
EOF

if [[ -f "$project_dir/AppIcon.icns" ]]; then
    /bin/cp "$project_dir/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string AppIcon.icns' "$plist"
fi

/usr/bin/plutil -lint "$plist"
/usr/bin/codesign --force --sign - "$app"
/usr/bin/codesign --verify --strict --verbose=2 "$app"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app" "$stage_dir/AsteraDMXMidiBridge.zip"
/bin/mv -f -- "$stage_dir/AsteraDMXMidiBridge.zip" "$output_zip"
print -r -- "$output_zip"
