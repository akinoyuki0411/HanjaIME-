# 한지미 노치 — 재구축 검토본

MIT Atoll 기반의 독립 노치 앱. Face는 후속 결합하며 이 빌드에는 포함하지 않습니다.

설정의 표시 언어에서 한국어와 영어를 선택합니다. 홈에는 미디어·일정·타이머·메모·할 일·거울 위젯을 선택해 배치하며, 설정 왼쪽 스위치로 켜고 끄며, 홈 미리보기에서 순서를 드래그하고 선택한 위젯의 너비를 조절합니다. 위젯 크기는 정해진 최소·최대 범위 안에서 저장되고 노치 폭도 화면 범위 안에서 따라 늘어납니다. 파일 보관함은 파일·링크·텍스트를 지원하며 AirDrop 영역의 좌우 위치도 설정 미리보기에서 바꿉니다. 별도의 도구 탭·단축어 기능·고정 버튼은 제거했습니다. 커서를 올리면 살짝 커지고 클릭하면 열리며, 커서가 나가면 접힙니다. ⌥⌘N으로도 열고 닫을 수 있습니다.

앨범을 누르면 제공된 재생 링크를 열며, 주소를 얻지 못하면 재생 앱을 엽니다. 별 버튼의 실제 즐겨찾기 변경은 Apple Music에만 연결되며 자동화 권한이 필요할 수 있습니다. 설정 스위치·너비 변경과 새 홈 화면은 실제 UI에서 확인했습니다. 음악 즐겨찾기와 재생 위치 변경의 실기 검증은 아직 완료하지 않았습니다.

사용자 입력기, 얼굴 특징, 비밀번호를 가져오거나 삭제하지 않습니다. 캘린더·카메라·블루투스·손쉬운 사용 등은 각 기능에 필요한 권한을 사용합니다. 비공개 미디어 및 밝기 API는 macOS 변경에 따라 동작하지 않을 수 있습니다.

## 빌드

Xcode Swift 6 도구 체인과 CMake가 필요합니다.

1. `swift build -c release`
2. `cmake -S ThirdParty/MediaRemoteAdapter -B ../build/notch-rebuild/media-build`
3. `cmake --build ../build/notch-rebuild/media-build --target MediaRemoteAdapter`
4. `python3 scripts/package-preview.py`

마지막 단계는 새 임시 폴더에 로컬 검토용 앱을 만듭니다. 현재 전체 기능 동등성·공개 배포가 완료된 버전이 아닙니다. 자세한 확인 범위는 [재구축 상태](docs/REBUILD_STATUS.md)를 참고하세요.

## 저작권 고지

Atoll: Copyright (c) 2026 Rut Mehta, MIT. [LICENSE](LICENSE), [원본](https://github.com/rutmehta/Atoll).

MediaRemoteAdapter: Copyright (c) 2025 Jonas van den Berg and contributors, BSD-3-Clause. [LICENSE](ThirdParty/MediaRemoteAdapter/LICENSE), [원본](https://github.com/ungive/mediaremote-adapter).

한지미 수정: 한국어 설정, 실행/데이터 영역 분리, 자체 미디어 프로토콜 연결, 불필요한 업데이트·에이전트·디버그 기능 제외.
