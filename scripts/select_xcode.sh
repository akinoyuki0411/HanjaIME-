#!/bin/bash
# Select within this process before Apple's python3/xcrun shims start.
hanjaime_xcode_version() {
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$1/../Info.plist" 2>/dev/null
}

hanjaime_choose_xcode27() {
  local candidate version major
  for candidate in "$@"; do
    [ -n "$candidate" ] || continue
    if [[ "$candidate" == *.app ]]; then
      candidate="$candidate/Contents/Developer"
    fi
    [ -x "$candidate/usr/bin/xcodebuild" ] || continue
    version="$(hanjaime_xcode_version "$candidate")" || continue
    major="${version%%.*}"
    [[ "$major" =~ ^[0-9]+$ ]] || continue
    [ "$major" -ge 27 ] || continue
    export DEVELOPER_DIR="$candidate"
    printf 'HanjaIME: Xcode %s 선택: %s\n' "$version" "$candidate" >&2
    return 0
  done
  printf '%s\n' \
    'macOS 27에서는 Xcode 27 전체 버전이 필요합니다.' \
    'https://developer.apple.com/download/ 에서 Xcode 27 베타를 받으세요.' \
    'Xcode-beta.app을 응용 프로그램 폴더로 옮기고 한 번 열어 초기 설치를 마친 뒤 다시 실행하세요.' >&2
  if [ -n "${DEVELOPER_DIR:-}" ]; then
    printf '지정된 DEVELOPER_DIR을 사용하지 못했습니다: %s\n' "$DEVELOPER_DIR" >&2
  fi
  return 1
}

hanjaime_select_xcode() {
  local host_version host_major selected
  [ "$(uname -s)" = Darwin ] || return 0
  host_version="$(/usr/bin/sw_vers -productVersion)" || return 1
  host_major="${host_version%%.*}"
  [[ "$host_major" =~ ^[0-9]+$ ]] || return 1
  [ "$host_major" -ge 27 ] || return 0
  if [ -n "${DEVELOPER_DIR:-}" ]; then
    # An explicit developer selection is never silently overridden.
    hanjaime_choose_xcode27 "$DEVELOPER_DIR"
    return $?
  fi
  selected="$(/usr/bin/xcode-select -p 2>/dev/null)" || selected=""
  hanjaime_choose_xcode27 "$selected" \
    /Applications/Xcode.app/Contents/Developer \
    /Applications/Xcode-beta.app/Contents/Developer \
    /Applications/Xcode*.app/Contents/Developer \
    "$HOME"/Applications/Xcode*.app/Contents/Developer
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  hanjaime_select_xcode || exit 1
  printf '%s' "${DEVELOPER_DIR:-}"
fi
