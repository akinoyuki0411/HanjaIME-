# GitHub 배포와 업데이트 (0.9.4)

저장소: https://github.com/akinoyuki0411/HanjaIME-

## ZIP은 어디에 올리나요?

저장소의 일반 파일 목록에는 소스, README, 라이선스와 재빌드 문서를 올립니다. 설치 ZIP은 **Releases → Draft a new release → Attach binaries**에 올립니다.

1. 배포 폴더 내용을 저장소 루트에 커밋합니다. `dist`, `build`, 로컬 로그, 개인 단어 파일, 이전 ZIP은 제외합니다. `CorrespondingSource`, `licenses`, `patches`와 빌드 스크립트는 유지합니다.
2. 버전 태그 `v0.9.4`를 만들고 제목은 `HanjaIME 0.9.4`로 지정합니다.
3. `HanjaIME_v0.9.4.zip`과 `.zip.sha256`을 릴리스 첨부파일로 올립니다.
4. 변경 내역과 지원 조건(Apple Silicon, 개발 서명, Xcode 필요 가능)을 적습니다.
5. 미리보기 검증 중에는 Draft로 보관하고 준비되면 공개합니다. 앱은 Draft와 prerelease를 설치 대상으로 취급하지 않습니다.

## 실제 구현된 범위

0.9.4부터 앱은 GitHub REST API의 `/repos/akinoyuki0411/HanjaIME-/releases/latest`를 읽습니다. `0.0.0` 형식 버전을 숫자로 비교하고, 최신 릴리스의 `HanjaIME_v버전_설명.zip`을 찾습니다. GitHub의 SHA-256 digest가 없거나 크기·해시가 맞지 않는 첨부파일은 받지 않거나 저장을 거부합니다.

자동 확인과 자동 다운로드는 설정에서 선택합니다. 파일은 사용자 Application Support의 HanjaIME/Updates에 보관하며 버튼으로 Finder에서 확인할 수 있습니다. ZIP의 압축 해제·설치·실행은 자동으로 하지 않습니다. 0.8.13 이하에는 이 기능이 없으므로 0.9.4까지는 직접 설치해야 합니다.

이 해시 검사는 GitHub에 올라온 파일과의 일치 여부를 확인하는 것입니다. Developer ID 공증이나 별도의 개발자 업데이트 서명을 대신하지 않습니다. 무인 자동 설치는 Sparkle 등 서명된 업데이트 체계와 입력기 종료·재등록·실패 복원 검증 후 추가할 수 있습니다.

## 웹사이트

현재 앱의 웹사이트는 위 GitHub 저장소 소개(README), 도움말은 README, 소스코드는 저장소, 버그 신고는 Issues로 연결됩니다. 별도의 GitHub Pages 사이트가 공개되면 웹사이트 주소만 바꾸면 됩니다. 아직 없는 Pages 주소를 제품에 넣지 않았습니다.

## 근거

- https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository
- https://docs.github.com/en/rest/releases/assets
- https://sparkle-project.org/documentation/
