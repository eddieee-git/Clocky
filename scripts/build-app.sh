#!/bin/zsh
# build/Clocky.app과 배포용 build/Clocky.dmg를 만든다. Xcode 없이 Command Line Tools만으로 빌드한다.
# Apple 실리콘 Mac 전용이다.
set -e
cd "$(dirname "$0")/.."

swift build -c release --arch arm64

app=build/Clocky.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/arm64-apple-macosx/release/Clocky "$app/Contents/MacOS/Clocky"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
# 개발자 인증서가 없으므로 임시 서명만 한다. 강화 런타임(--options runtime)을 켜서 실행 중인 앱에 다른 코드를 끼워 넣지 못하게 한다.
codesign --force --sign - --options runtime "$app"

# 내려받은 쪽에서 응용 프로그램 폴더로 끌어다 놓을 수 있게 바로가기를 함께 넣는다.
staging=build/dmg
rm -rf "$staging" build/Clocky.dmg
mkdir -p "$staging"
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"
hdiutil create -quiet -volname Clocky -srcfolder "$staging" -format UDZO build/Clocky.dmg
rm -rf "$staging"

echo "$app"
echo build/Clocky.dmg
