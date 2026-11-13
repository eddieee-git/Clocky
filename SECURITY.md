# 보안 · Security

[한국어](#한국어) · [English](#english)

## 한국어

### 지원하는 버전

가장 최근 릴리스만 고칩니다. Clocky는 하루에 한 번 새 버전을 확인하므로 최신 버전으로 업데이트해 주세요.

### 취약점 알리기

보안 문제는 공개 이슈에 올리지 말고, 저장소의 **Security → Report a vulnerability**로 비공개로 알려 주세요. 다음을 적어 주시면 도움이 됩니다.

- Clocky와 macOS 버전
- 무엇이 문제인지, 다시 일으키는 방법
- 예상되는 피해(예: 다른 파일을 읽을 수 있음, 업데이트를 바꿔치기할 수 있음)

개인이 만드는 무료 앱이라 답이 늦을 수 있지만, 확인되면 고친 버전을 릴리스하고 변경 기록에 적습니다.

### Clocky가 지키는 것

- 앱 샌드박스와 강화 런타임. 네트워크는 iCal 주소 받기와 GitHub 업데이트 확인에만 쓰고, 자기 폴더 밖의 파일은 직접 고른 소리 파일과 업데이트 dmg(다운로드 폴더)만 다룹니다.
- 업데이트는 https GitHub 주소에서만 받고, GitHub가 알려 준 SHA-256과 만든 사람의 Ed25519 서명(버전 포함)이 맞을 때만 엽니다.
- iCal 주소는 https만 받고 화면에는 비밀 부분을 가립니다.
- Apple 공증은 받지 않았습니다. 처음 실행할 때 보안 경고가 나오는 이유입니다([설치 안내](docs/install.md)).

## English

### Supported versions

Only the latest release gets fixes. Clocky checks for a new version once a day, so please keep it up to date.

### Reporting a vulnerability

Please don't open a public issue for a security problem. Report it privately with **Security → Report a vulnerability** in this repository. It helps to include:

- Your Clocky and macOS versions
- What the problem is and how to reproduce it
- What an attacker could do (for example, read other files or replace an update)

Clocky is a free app made by one person, so replies may take a while. Confirmed problems are fixed in a new release and noted in the changelog.

### What Clocky protects

- App Sandbox and Hardened Runtime. Clocky uses the network only to download iCal addresses and to check GitHub for updates. Outside its own folder, it touches only sound files you pick and the update dmg in your Downloads folder.
- Updates come only from https GitHub addresses, and Clocky opens one only when it matches the SHA-256 from GitHub and the developer's Ed25519 signature, which includes the version.
- Clocky accepts https iCal addresses only and hides the secret part on screen.
- Clocky isn't notarized by Apple, which is why macOS shows a security warning on first launch ([install guide](docs/install.en.md)).
