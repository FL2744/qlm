#!/bin/zsh
set -eu
cd "${0:A:h}"
mkdir -p build/qlm.app/Contents/MacOS build/qlm.app/Contents/Resources
for arch in arm64 x86_64; do
  swiftc -swift-version 5 -target "$arch-apple-macosx15.0" -O -module-cache-path build/module-cache -framework AppKit -framework UniformTypeIdentifiers Sources/*.swift -o "build/qlm-$arch"
done
lipo -create build/qlm-arm64 build/qlm-x86_64 -output build/qlm.app/Contents/MacOS/qlm
swift -module-cache-path build/module-cache tools/Icon.swift build/qlm.iconset
iconutil -c icns build/qlm.iconset -o build/qlm.app/Contents/Resources/qlm.icns
cp build/qlm.iconset/icon_256x256@2x.png build/qlm.app/Contents/Resources/Wordmark.png
swift -module-cache-path build/module-cache tools/Favicon.swift build/qlm.app/Contents/Resources/Favicon.png
mkdir -p build/native-icon
xcrun actool Assets/qlm.icon --compile build/native-icon --platform macosx --minimum-deployment-target 15.0 --app-icon qlm --output-partial-info-plist build/native-icon/Info.plist --output-format human-readable-text > build/native-icon/compile.log
cp build/native-icon/Assets.car build/native-icon/qlm.icns build/qlm.app/Contents/Resources/
python3 tools/bundle.py
codesign --force --deep --sign - build/qlm.app
printf 'Built %s/build/qlm.app\n' "$PWD"
