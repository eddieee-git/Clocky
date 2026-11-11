#!/bin/zsh
# 창을 실제로 띄워 보는 시험. Tests/GUI의 시나리오마다 앱 소스와 함께 따로 빌드해 돌린다.
# 시나리오는 앱 안쪽 값을 직접 고치므로, 임시 폴더에 소스를 복사하고 private를 풀어서 빌드한다.
# 하네스는 번들이 없어 "Clocky"라는 별도 설정 도메인을 쓰고, 시나리오가 시작과 끝에 그 도메인을 비운다.
# 실제 앱의 설정(com.eddieee.Clocky)에는 손대지 않는다.
#
# 쓰는 법: scripts/gui-test.sh [시나리오 이름...]   예: scripts/gui-test.sh keyboard windows
#   readme-shots 시나리오는 README 이미지를 build/shots에 찍는다(한국어·영어).
set -e
cd "$(dirname "$0")/.."
root=$PWD
work=$(mktemp -d)
shots=$root/build/shots
mkdir -p "$work/Sources/Clocky" "$shots"
trap 'rm -rf "$work"' EXIT
sed '/testTarget/d' Package.swift > "$work/Package.swift"

scenarios=("$@")
(( ${#scenarios} )) || scenarios=(basics restore keyboard windows calendar calendar-add update)
failed=0
for name in $scenarios; do
    rm -f "$work"/Sources/Clocky/*.swift(N)
    for f in Sources/Clocky/*.swift; do
        [[ ${f:t} == main.swift ]] || sed 's/private(set) //g; s/private //g' "$f" > "$work/Sources/Clocky/${f:t}"
    done
    cp "Tests/GUI/$name.swift" "$work/Sources/Clocky/main.swift"
    (cd "$work" && swift build 2>&1 | grep -E "error|warning" || true)
    langs=(ko)
    [[ $name == readme-shots || $name == windows || $name == calendar || $name == update ]] && langs=(${=CLOCKY_LANGS:-ko en})
    for lang in $langs; do
        echo "== $name ($lang)"
        home=$(mktemp -d)
        # 시나리오가 멈춰도 40초 뒤에는 끝낸다.
        HOME=$home CFFIXED_USER_HOME=$home "$work/.build/debug/Clocky" "$shots" $lang > "$work/out.txt" 2>&1 &
        pid=$!
        ( sleep 40; kill $pid 2>/dev/null ) &
        wait $pid || true
        grep -E "FAIL|ALL PASS|FAILURES" "$work/out.txt" || true
        grep -q "FAIL" "$work/out.txt" && failed=1
        rm -rf "$home"
    done
done
exit $failed
