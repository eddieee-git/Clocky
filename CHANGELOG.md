# Changelog

[한국어](#한국어) · [English](#english)

## 한국어

### 다음 버전

- 업데이트 서명: 새 버전은 만든 사람의 서명(Ed25519)이 맞을 때만 받는다. 버전도 함께 서명해 옛 파일을 새 버전으로 속이지 못한다. 서명이 없는 릴리스는 릴리스 페이지로 안내한다.
- dmg 안에서 바로 실행하면 Applications 폴더로 옮기라고 알린다.
- 업데이트 확인과 개인정보 안내 문구를 정확하게 고쳤다(GitHub가 보는 것, iCal 주소가 저장되는 곳).

### 0.2.1 — 업데이트 확인

- 업데이트 확인: 하루에 한 번 GitHub에 새 버전이 있는지 묻고, 있으면 메뉴바 메뉴와 설정 → 일반에 알린다. 누르면 dmg를 다운로드 폴더에 받아 SHA-256을 확인하고 연다. 설정에서 끌 수 있다.

### 0.2.0 — 첫 공개판

**타이머와 알람**
- 넘김시계 숫자판이 있는 시계 창. 창 크기는 고정이고 옮겨 둔 자리를 기억한다.
- 타이머 여러 개(이름, 시간, 대기·진행·일시정지·울림), 앱을 다시 켜도 이어서 돈다.
- 알람 여러 개(이름, 시각, 매일·평일·주말·한 번·요일 지정, 켜기·끄기, 알람별 소리), 울리기까지 남은 시간 표시.
- 울리기 전 깜빡임, 끌 때까지 되풀이하는 소리, 다시 울림. 울릴 때 쓰던 앱의 키보드를 빼앗지 않는다.
- 지운 항목 되돌리기(⌘Z), 시간대·시계 변경과 잠자기 뒤에도 정확한 시각.

**캘린더 일정 알림**
- Mac 캘린더 앱 경유(시스템 설정 → 인터넷 계정의 구글 회사 계정 등). 캘린더별로 고른다.
- 구글 캘린더 iCal 주소(비공개 주소, 또는 이미 공개한 캘린더의 공개 주소). 반복·예외·시간대를 직접 해석한다.
- 알림 시점(정각, 1·5·10·15·30분 전), 종일·거절한 일정 빼기, 일정마다 이번 알림만 끄기.

**창과 설정**
- 메뉴바 남은 시간과 상태 줄, 전체 목록 창(검색, 정렬, 여러 개 선택, 일정 보기), 설정 창(일반, 타이머·알람, 소리, 캘린더, 단축키).
- 창 안 단축키와 전역 단축키(⌃⌥C 시계 창, ⌃⌥T 타이머, ⌃⌥X 울림 끄기).
- 내 소리 파일, 소리 크기, 타이머 시간 버튼 바꾸기.
- VoiceOver와 "동작 줄이기" 지원, 한국어·영어.

**보안**
- 앱 샌드박스와 강화 런타임. 인터넷은 넣은 iCal 주소에서 받아 올 때만, 캘린더 접근은 연동을 켰을 때만 쓴다.

**알려진 점**
- Apple 공증을 받지 않아 처음 실행할 때 보안 경고가 나온다. 업데이트하면 캘린더 접근을 다시 물을 수 있다.
- macOS 26에서 개발하고 시험했다. macOS 13·14·15에서는 아직 실행해 보지 않았다.

## English

### Next version

- Signed updates: Clocky downloads a new version only when its developer's signature (Ed25519) matches. The version is signed too, so an old file can't pass as a new version. For an unsigned release, Clocky points you to the release page.
- If you open Clocky straight from the dmg, it asks you to move it to the Applications folder.
- Clearer wording about update checks and privacy (what GitHub sees, where iCal addresses are stored).

### 0.2.1 — Update checks

- Update checks: once a day Clocky asks GitHub whether there's a new version and shows it in the menu bar menu and Settings → General. Click it to download the dmg to your Downloads folder, check its SHA-256, and open it. You can turn this off in Settings.

### 0.2.0 — First public release

**Timers and alarms**
- A clock window with flipping digit cards. It never changes size and remembers where you put it.
- Multiple timers (name, duration, ready/running/paused/ringing) that keep running after a restart.
- Multiple alarms (name, time, Daily/Weekdays/Weekends/Once/chosen days, on/off, per-alarm sound) with time left until each rings.
- A flashing warning before ringing, a sound that repeats until you stop it, and snooze. Ringing doesn't take the keyboard from the app you're using.
- Undo deletes (⌘Z), and correct times across time-zone changes, clock changes, and sleep.

**Calendar alerts**
- Through the Mac Calendar app (for example, a work Google account added in System Settings → Internet Accounts), with per-calendar selection.
- Google Calendar iCal addresses (the secret address, or the public address of a calendar that's already public). Clocky reads repeats, exceptions, and time zones itself.
- Alert timing (at start, or 1, 5, 10, 15, or 30 minutes before), skip all-day and declined events, and skip a single alert.

**Windows and settings**
- Menu bar countdown and status lines, an All Timers & Alarms window (search, sort, multiple selection, events), and Settings (General, Timers & Alarms, Sound, Calendar, Shortcuts).
- Window shortcuts and global shortcuts (⌃⌥C clock window, ⌃⌥T timer, ⌃⌥X stop ringing).
- Your own sound files, volume, and custom timer buttons.
- VoiceOver and Reduce Motion support; English and Korean.

**Security**
- App Sandbox and Hardened Runtime. Clocky uses the internet only to download the iCal addresses you add, and asks for calendar access only when you turn on the Mac Calendar option.

**Known issues**
- Clocky isn't notarized by Apple, so macOS shows a security warning on first launch. macOS may ask for calendar access again after an update.
- Developed and tested on macOS 26. Not yet run on macOS 13, 14, or 15.
