# Clocky 개발 안내

메뉴바에 사는 넘김시계 타이머·알람·캘린더 알림 앱. 사용자 문서는 README.md(한국어)·README.en.md, 설치는 docs/install*.md, 바뀐 점은 CHANGELOG.md. 이 파일은 개발을 이어받는 사람(과 Claude)을 위한 것이다.

## 지켜야 할 것

- 대화와 문서는 한국어가 기본. 사용자 문서는 한국어·영어를 함께 고친다(README, docs/install, CHANGELOG, 화면 문구).
- **Apple 계정이 필요한 기능은 쓰지 않는다**: iCloud, 공증(notarization), 알림 권한, Developer ID 등. 서명은 임시 서명(`codesign --sign -`)뿐이다. 그래서 처음 실행할 때 Gatekeeper 경고가 나오고, 업데이트하면 캘린더 접근을 다시 물을 수 있다(문서에 안내되어 있음).
- Apple 실리콘(arm64), macOS 13 이상. Xcode 없이 Command Line Tools만으로 빌드한다. 외부 라이브러리 없음.
- 시계 창 크기는 고정. 항상 위는 기본으로 켜져 있고 끌 수 있다. 핀은 닫기 버튼과 같은 줄. 울리기 10초 전부터 창이 깜빡인다(설정으로 바꿈). 알람에는 이름이 있다.
- 작업 순서: 구현 → 빌드 → /Applications에 다시 설치 → 사용자 확인 → 로컬 커밋 → **사용자가 "push해"라고 할 때만 push**.
- 커밋 작성자는 저장소에 설정된 eddieee-git noreply 주소.

## 구조 (Sources/Clocky)

| 파일 | 내용 |
|---|---|
| ClockStore.swift | 타이머·알람·일정 알림의 상태와 시간 계산, 저장(UserDefaults JSON), 옛 설정 옮기기, 울리기·다시 울림 |
| FlipTimerView.swift | 시계 창 SwiftUI 화면 |
| TimerWindow.swift | 시계 창(NSPanel), 울릴 때 클릭·키 가로채기, 창 단축키 |
| ListWindow.swift | 전체 목록 창 |
| SettingsWindow.swift | 설정 창(일반·타이머·알람·소리·캘린더·단축키), 업데이트 칸 |
| ClockySettings.swift | 설정 값, 알람 소리, **화면 문구 영어 표(`Localization.english`)** |
| ICalendar.swift / CalendarSync.swift | iCal 해석(RRULE·EXDATE·시간대 등)과 주소에서 받아 오기 |
| MacCalendarSource.swift | EventKit으로 Mac 캘린더 앱 일정 읽기 |
| UpdateChecker.swift | GitHub 최신 릴리스 확인, dmg를 다운로드 폴더에 받아 SHA-256 확인 후 열기 |
| HotKey.swift / MenuBarIcon.swift / AppDelegate.swift | 전역 단축키, 메뉴바 아이콘, 메뉴와 앱 연결 |

- 화면 문구는 `L("한국어")`로 쓰고 영어는 `Localization.english`에 넣는다. **표에 같은 열쇠가 두 번 들어가면 실행 중에 죽는다.**
- 샌드박스 권한(Resources/Clocky.entitlements): 네트워크 클라이언트, 캘린더, 사용자가 고른 파일 읽기, 다운로드 폴더 읽기·쓰기. 설정은 `~/Library/Containers/com.eddieee.Clocky`에 있다.
- `#if DEBUG`에서만 쓰는 시험용 설정: `debugAppVersion`, `debugUpdateURL`.

## 빌드와 시험

```bash
scripts/build-app.sh          # build/Clocky.app, build/Clocky-<버전>.dmg
scripts/test.sh               # 단위 시험(Swift Testing)
scripts/gui-test.sh           # 창을 띄우는 시험 전부. 이름을 주면 그것만: scripts/gui-test.sh update
scripts/gui-test.sh readme-shots   # README 이미지를 build/shots에 찍는다(한국어·영어)
swift scripts/make-icon.swift # 앱 아이콘 다시 그리기
```

- GUI 시험은 소스를 임시 폴더에 복사해 `private`를 풀고, 번들 없는 "Clocky" 설정 도메인으로 돈다. 실제 앱 설정에는 손대지 않는다.
- **화면이 잠겨 있으면 클릭이 창에 닿지 않아 `windows` 등이 실패한다.** 부하가 크면 시간에 민감한 확인이 가끔 실패하므로 다시 돌려 본다.
- 다시 설치: `osascript -e 'quit app "Clocky"'` → `rm -rf /Applications/Clocky.app` → `cp -R build/Clocky.app /Applications/` → `open /Applications/Clocky.app`.

## 릴리스

1. Resources/Info.plist의 `CFBundleShortVersionString`(예: 0.2.1)과 `CFBundleVersion`(빌드 번호, 하나씩 올림)을 올린다.
2. CHANGELOG.md의 한국어·영어 칸에 버전 제목과 바뀐 점을 적는다.
3. `scripts/build-app.sh`로 dmg를 만든다. 서명 키가 있으면 `build/Clocky-X.Y.Z.dmg.sig`도 함께 만든다(없으면 경고). `shasum -a 256 build/Clocky-X.Y.Z.dmg`를 적어 둔다.
4. 커밋하고 push한 뒤(사용자 허락이 있을 때), `gh release create vX.Y.Z build/Clocky-X.Y.Z.dmg build/Clocky-X.Y.Z.dmg.sig --title "Clocky X.Y.Z" --notes-file <노트> --latest`.
   - **0.2.2부터 앱은 `.sig`가 없거나 서명이 맞지 않는 릴리스는 받지 않는다.** `.sig`를 꼭 함께 올린다.
   - 파일 이름은 `Clocky-X.Y.Z.dmg`(0.2.1까지는 `Clocky.dmg`). 앱은 `.dmg`로 끝나는 첫 파일을 받으므로 릴리스에 dmg는 하나만 올린다. 태그는 `v` + 버전. 초안·시험판은 앱이 무시한다.
   - 노트 첫머리 약 600자가 앱의 업데이트 창에 보이므로 바뀐 점을 맨 앞에 한국어·영어로 쓴다. 설치 방법과 SHA-256을 함께 적는다.
5. `curl -s https://api.github.com/repos/eddieee-git/mac-app-clocky/releases/latest`로 태그와 dmg의 `digest`가 맞는지 확인한다.

## 릴리스 서명 키

- Ed25519 비밀키는 저장소 밖 `~/.clocky-release/signing-key`(권한 600)에 있다. 공개키는 `UpdateChecker.releasePublicKey`에 들어 있다.
- `swift scripts/release-key.swift public`은 공개키를 보여 준다(없으면 새로 만든다). `sign <dmg> <버전>`은 `<dmg>.sig`를 만든다. 서명 내용은 `clocky-release:<버전>:<dmg SHA-256>`.
- **키를 잃어버리면 이미 배포한 앱이 새 버전을 받지 못한다.** 안전한 곳(암호 관리자 등)에 백업하고, 다른 Mac에서 릴리스하려면 같은 자리에 복사한다. 키를 바꾸면 사용자는 한 번 직접 업데이트해야 한다.
- 단위 시험 `서명_스크립트와_앱의_공개키가_맞다`는 키가 있는 Mac에서만 돌며, 앱의 공개키가 비밀키와 짝인지 확인한다.

## 정해 둔 것

- iCal 비밀 주소는 키체인이 아니라 UserDefaults에 둔다. 임시 서명은 빌드마다 서명이 달라져, 키체인에 두면 업데이트할 때마다 macOS가 키체인 접근 암호를 묻기 때문이다. 대신 문서에 저장 위치와 백업에 들어간다는 점을 적었다.

## 남은 일

- Mac 캘린더 앱 연동은 실제 캘린더로 아직 시험하지 못했다(다른 Mac에서 확인 예정).
- macOS 13·14·15에서는 아직 실행해 보지 않았다.
- Floaty(별도 저장소)의 README에 있는 Clocky 소개 문구는 Floaty 쪽에서 고친다.
