#!/bin/zsh
# Usage: ./build.sh            -> build/DisplayDial-CN.app
#        ./build.sh install    -> also copies it to /Applications and launches it
#        ./build.sh check      -> hardware self-check (DDC write round-trip)
#        ./build.sh screenshots -> renders docs/panel-{light,dark}.png from the live monitor
#        ./build.sh dmg        -> also packages build/DisplayDial.dmg and .zip for sharing
set -e
cd "${0:a:h}"
if [[ $1 == check ]]; then
  mkdir -p build
  swiftc Sources/DDC.swift Tests/main.swift -o build/check
  exec build/check
fi
# --- SDK selection ----------------------------------------------------------
# macOS 27's SwiftUICore declares SwiftUI's @State/@FocusState as external macros
# that live in the SwiftUIMacros plugin. That plugin ships with Xcode, but not with
# the standalone Command Line Tools toolchain, so a CLT-only Mac fails to compile
# with "external macro implementation type 'SwiftUIMacros.StateMacro' could not be
# found". SDKs before macOS 27 declare them as plain property wrappers, so probe
# the installed SDKs and build against the newest one this toolchain can really
# compile. An explicit SDKROOT always wins.
sdk_probe() {
  printf 'import SwiftUI\nstruct SDKProbe { @State var value = 0 }\n' > build/.sdk-probe.swift
  swiftc -typecheck -target arm64-apple-macos14.0 -sdk "$1" build/.sdk-probe.swift >/dev/null 2>&1
}
resolve_sdk() {
  if [[ -n $SDKROOT ]]; then print -r -- $SDKROOT; return; fi
  mkdir -p build
  local devdir default_sdk sdk phys ver dir s
  devdir=$(xcode-select -p 2>/dev/null)
  default_sdk=$(xcrun --show-sdk-path 2>/dev/null)
  local -a candidates=() entries=()
  local -A seen=()
  if [[ -n $default_sdk && -d $default_sdk ]]; then
    phys=$(cd "$default_sdk" && pwd -P)
    seen[$phys]=1
    candidates+=($phys)
  fi
  for dir in "$devdir/Platforms/MacOSX.platform/Developer/SDKs" "$devdir/SDKs"; do
    if [[ -d $dir ]]; then
      for s in "$dir"/MacOSX*.sdk; do
        if [[ -d $s ]]; then
          phys=$(cd "$s" && pwd -P)
          if [[ -z ${seen[$phys]} ]]; then
            seen[$phys]=1
            ver=${phys:t}; ver=${ver#MacOSX}; ver=${ver%.sdk}
            entries+=("$ver"$'\t'"$phys")
          fi
        fi
      done
    fi
  done
  # Newest SDK first.
  for sdk in ${(f)"$(print -l -- $entries | sort -t$'\t' -k1,1Vr | cut -f2)"}; do
    candidates+=($sdk)
  done
  for sdk in $candidates; do
    if sdk_probe $sdk; then print -r -- $sdk; return; fi
  done
  print -r -- $default_sdk
}
SDK=$(resolve_sdk)
rm -f build/.sdk-probe.swift
if [[ -z $SDK ]]; then
  echo "No usable macOS SDK found; install Xcode or set SDKROOT." >&2
  exit 1
fi
echo "Using SDK $SDK"
# Version comes from the latest vX.Y.Z git tag; the build number is the commit count.
VERSION=$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null | sed 's/^v//')
VERSION=${VERSION:-0.0.0}
if [[ $1 == screenshots ]]; then
  mkdir -p build
  # A bare executable has no bundle, so embed an Info.plist for the panel's version label.
  printf '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleShortVersionString</key><string>%s</string></dict></plist>' $VERSION > build/screenshots-Info.plist
  swiftc -O -D SCREENSHOTS -target arm64-apple-macos14.0 -sdk $SDK Sources/*.swift -o build/screenshots \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker build/screenshots-Info.plist
  exec build/screenshots
fi
APP=build/DisplayDial-CN.app
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 1)
rm -rf $APP && mkdir -p $APP/Contents/{MacOS,Resources}
cp Resources/AppIcon.icns Resources/MenuBarIconTemplate.pdf $APP/Contents/Resources/
swiftc -O -target arm64-apple-macos14.0 -sdk $SDK Sources/*.swift -o $APP/Contents/MacOS/DisplayDialCN
cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>DisplayDial CN</string>
  <key>CFBundleDisplayName</key><string>DisplayDial 中文版</string>
  <key>CFBundleIdentifier</key><string>com.xppxpp.displaydialcn</string>
  <key>CFBundleExecutable</key><string>DisplayDialCN</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>© 2026 Grab Connected Tech LLC. grabians.com</string>
</dict></plist>
PLIST
codesign --force -s - $APP
echo "Built $APP $VERSION ($BUILD)"
if [[ $1 == install ]]; then
  pkill -x DisplayDialCN || true
  rm -rf /Applications/DisplayDial-CN.app && cp -R $APP /Applications/
  open /Applications/DisplayDial-CN.app
  echo "Installed to /Applications"
fi
if [[ $1 == dmg ]]; then
  STAGE=build/dmg && rm -rf $STAGE build/DisplayDial-CN.dmg build/DisplayDial-CN.zip && mkdir -p $STAGE
  cp -R $APP $STAGE/ && ln -s /Applications $STAGE/Applications
  hdiutil create -volname "DisplayDial 中文版" -srcfolder $STAGE -format UDZO -quiet build/DisplayDial-CN.dmg
  rm -rf $STAGE
  ditto -c -k --keepParent $APP build/DisplayDial-CN.zip
  echo "Created build/DisplayDial-CN.dmg and build/DisplayDial-CN.zip"
fi
