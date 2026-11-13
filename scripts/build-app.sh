#!/bin/zsh
# build/Clocky.app과 배포용 build/Clocky-<버전>.dmg(예: Clocky-0.2.2.dmg)를 만든다. Xcode 없이 Command Line Tools만으로 빌드한다.
# Apple 실리콘 Mac 전용이다.
set -e
cd "$(dirname "$0")/.."

swift build -c release --arch arm64
version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
dmg=build/Clocky-$version.dmg

app=build/Clocky.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/arm64-apple-macosx/release/Clocky "$app/Contents/MacOS/Clocky"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
# 샌드박스를 켜기 전 판의 설정을 컨테이너로 옮기는 안내서. 처음 실행할 때 macOS가 읽는다.
cp Resources/container-migration.plist "$app/Contents/Resources/container-migration.plist"
# 개발자 인증서가 없으므로 임시 서명만 한다. 강화 런타임(--options runtime)을 켜서 실행 중인 앱에 다른 코드를 끼워 넣지 못하게 하고,
# 앱 샌드박스를 켠다.
codesign --force --sign - --options runtime --entitlements Resources/Clocky.entitlements "$app"

# 내려받은 쪽에서 응용 프로그램 폴더로 끌어다 놓을 수 있게 바로가기를 함께 넣는다.
staging=build/dmg
rm -rf "$staging" build/Clocky*.dmg
mkdir -p "$staging"
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"
hdiutil create -quiet -volname Clocky -srcfolder "$staging" -format UDZO "$dmg"
rm -rf "$staging"

echo "$app"
echo "$dmg"
