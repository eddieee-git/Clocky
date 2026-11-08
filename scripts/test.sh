#!/bin/zsh
# 시험을 돌린다. Xcode 없이 Command Line Tools에 든 Swift Testing을 쓰는데,
# swift test가 그 위치를 스스로 찾지 못하므로 경로를 알려 준다.
set -e
cd "$(dirname "$0")/.."
dev=/Library/Developer/CommandLineTools/Library/Developer
# Swift Testing이 macOS 14용으로 빌드돼 있어 시험만 14를 대상으로 빌드한다. 앱은 그대로 13 이상에서 돈다.
swift test --scratch-path .build/tests \
    -Xswiftc -target -Xswiftc arm64-apple-macosx14.0 \
    -Xswiftc -F -Xswiftc $dev/Frameworks \
    -Xlinker -rpath -Xlinker $dev/Frameworks \
    -Xlinker -rpath -Xlinker $dev/usr/lib \
    "$@"
