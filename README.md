# HanjaIME · 한지미

한국어 두벌식 입력 중 한자·일본어 신자체·관련 이모지를 고르는 macOS 입력기입니다. 구름(Gureum)과 libhangul을 기반으로 합니다.

[한국어 설치 안내](설치와사용법.md) · [English](README_EN.md) · [日本語](README_JA.md) · [변경 내역](CHANGELOG.md)

## 설치

1. [Releases](https://github.com/akinoyuki0411/HanjaIME-/releases)에서 `HanjaIME_v0.8.14_International.zip`을 받습니다. 릴리스가 없다면 아직 공개 배포 전입니다.
2. 새 폴더에 압축을 풀고 `repair_and_install.command`를 실행합니다. 현재 설치기는 Xcode와 명령줄 개발 도구로 검증·빌드를 수행할 수 있습니다.
3. macOS 입력 소스에서 **HanjaIME 두벌식**을 선택합니다. 목록에 바로 나타나지 않으면 로그아웃 후 다시 로그인합니다.
4. 입력 메뉴 → 환경설정 → 일반에서 **한국어 / English / 日本語**를 선택합니다. 화면 언어만 변경하며 입력 방식은 한국어 두벌식입니다.

입력 중 후보가 나타나면 Space로 후보를 선택/이동하고 Enter로 확정합니다. Shift+Space는 한글을 유지한 채 공백을 넣습니다. Esc는 변환을 취소합니다. 개인 단어는 환경설정 → 개인 단어에서 관리합니다.

## 업데이트

환경설정 → 정보에서 새 버전 확인, 자동 확인, 업데이트 ZIP 자동 다운로드를 사용할 수 있습니다. 자동 확인은 기본 꺼짐이며 켜면 하루 간격으로 GitHub의 최신 정식 릴리스를 조회합니다. 다운로드 기능은 GitHub가 제공한 SHA-256과 파일 크기를 확인합니다. 설치나 실행을 자동으로 수행하지 않습니다. 내려받은 ZIP을 풀어 설치 명령을 실행하세요.

새 버전이 처음 실행될 때 변경 내역이 한 번 표시됩니다. 이미 본 버전에는 반복 표시하지 않습니다.

## 도움과 문의

- [버그 알리기](https://github.com/akinoyuki0411/HanjaIME-/issues/new): 발생 앱, macOS 버전, 한지미 버전, 입력 전환 방법과 재현 순서를 적어 주세요. 개인 문장이나 비밀번호는 포함하지 마세요.
- [소스코드](https://github.com/akinoyuki0411/HanjaIME-)
- 이메일: [akinoyuki0122@gmail.com](mailto:akinoyuki0122@gmail.com)
- 후원 페이지는 준비 중이며 현재 결제를 받지 않습니다.

## 배포 및 라이선스

현재 빌드는 Apple Silicon용 개발 서명판입니다. Developer ID 공증과 Intel 빌드는 포함하지 않습니다. 공식 구름 입력기와 별도로 설치됩니다. 설치된 앱은 `~/Library/Input Methods/HanjaIME.app`에 있으므로 다운로드한 원본 폴더를 지워도 설치된 입력기 파일이 삭제되지 않습니다.

개인 단어와 학습 데이터는 배포본에 포함하지 않습니다. [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), [licenses](licenses), [대응 소스](CorrespondingSource), [재빌드 안내](REBUILD.md)를 함께 배포합니다. 구성요소별 라이선스와 재배포 의무를 확인하세요.
